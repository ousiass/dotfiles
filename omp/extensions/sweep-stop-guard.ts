// sweep 系スキル用の停止ガード。
// Claude Code 版の Stop Hook (`.claude/hooks/check-issue-queue.sh` /
// `check-sweep-state.sh`) と同じ役割を omp ネイティブの `session_stop` で行う。
// omp は settings.json の hooks.Stop（シェル形式）を解釈しないため、拡張で実装する。
//
// - `.sweep/queue.txt` に未処理 Issue が残っている、または
//   `.sweep/state.json` が `phase != "terminal"` の間は停止をブロックする
// - lock が stale（heartbeat 2時間超）/ 不在 / 他セッション所有なら停止を許可する
// - `session_stop` はメインセッションでのみ発火する（サブエージェントは対象外）
// - `decision: "block"` は継続上限（advisory の 8 回）を消費しない

import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";

const STALE_THRESHOLD_SEC = 7200; // 2時間

function resolveSweepDir(): string | null {
    // worktree 内のサブスキルと同じファイルを見るため、常にメインリポジトリ側を指す。
    // omp に CLAUDE_PROJECT_DIR 相当の変数は無い（存在するのは OMP_DAEMON_PROJECT_DIR
    // 等の内部用途のみ）。Claude Code 併用時のフォールバックとしてのみ見る。
    const fromEnv = process.env.CLAUDE_PROJECT_DIR;
    if (fromEnv) return join(fromEnv, ".sweep");
    try {
        const gitCommonDir = execFileSync(
            "git",
            ["rev-parse", "--path-format=absolute", "--git-common-dir"],
            { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] },
        ).trim();
        if (!gitCommonDir) return null;
        return join(dirname(gitCommonDir), ".sweep");
    } catch {
        return null;
    }
}

function readFile(path: string): string | null {
    try {
        return existsSync(path) ? readFileSync(path, "utf8") : null;
    } catch {
        return null;
    }
}

function parentPid(pid: number): number | null {
    try {
        const status = readFileSync(`/proc/${pid}/status`, "utf8");
        const match = status.match(/^PPid:\s*(\d+)$/m);
        return match ? Number(match[1]) : null;
    } catch {
        return null;
    }
}

function isAncestor(ancestor: number, descendant: number): boolean {
    let pid: number | null = descendant;
    while (pid !== null && pid > 1) {
        if (pid === ancestor) return true;
        pid = parentPid(pid);
    }
    return false;
}

function isAlive(pid: number): boolean {
    try {
        process.kill(pid, 0);
        return true;
    } catch (err) {
        // EPERM は「プロセスは居るが権限が無い」。存在しないのは ESRCH のときだけ。
        return (err as NodeJS.ErrnoException)?.code === "EPERM";
    }
}

// lock は `<PID>:<epoch秒>`。フェーズ0 が `echo "$PPID:$(date +%s)"` で書く。
// 「このセッションが持ち主か」を PID の親子関係で判定する。同じリポジトリで
// 別の作業をしているだけのセッションまで止めると、そちらは lock を解除できず
// 停止ブロックと無限に往復するため。
type LockState = "absent" | "stale" | "foreign" | "owned";

function inspectLock(sweepDir: string): LockState {
    const raw = readFile(join(sweepDir, "lock"));
    if (raw === null) return "absent";

    const [pidField, tsField] = raw.trim().split(":");
    const timestamp = Number(tsField);
    if (!Number.isInteger(timestamp) || timestamp <= 0) return "stale";
    if (Math.floor(Date.now() / 1000) - timestamp > STALE_THRESHOLD_SEC) return "stale";

    const lockPid = Number(pidField);
    if (!Number.isInteger(lockPid) || lockPid <= 0) return "owned";

    // bash ツールの $PPID はこのプロセス自身とも、その子シェルともなり得るので双方向に見る。
    const self = process.pid;
    if (lockPid === self || isAncestor(lockPid, self) || isAncestor(self, lockPid)) return "owned";

    // 生きている別セッションの sweep → こちらは止まってよい。
    return isAlive(lockPid) ? "foreign" : "owned";
}

function queueBlockReason(sweepDir: string): string | null {
    const queue = readFile(join(sweepDir, "queue.txt"));
    if (!queue) return null;
    const entries = queue.split("\n").filter((line) => line.trim().length > 0);
    if (entries.length === 0) return null;

    // メッセージは 1 行に抑える。停止のたびに context へ積まれるため。
    return `issue-sweep: 未処理 ${entries.length} 件（次 #${entries[0].trim()}）。フェーズ2 を続行。待つだけなら停止せず \`sleep 60\` を 1 コマンド実行して再確認する。`;
}

function stateBlockReason(sweepDir: string): string | null {
    const raw = readFile(join(sweepDir, "state.json"));
    if (!raw) return null;

    let state: { phase?: string; skill?: string; queue_remaining?: unknown };
    try {
        state = JSON.parse(raw);
    } catch {
        return null;
    }
    if (state.phase === "terminal" || !state.phase) return null;

    const skill = state.skill ?? "sweep";
    const remaining = state.queue_remaining ?? "-";
    return `${skill}: phase=${state.phase}（残 ${remaining}）で terminal 未到達。閾値到達まで継続するか termination_reason を設定して terminal 化してから停止（推定 terminal 禁止）。待つだけなら停止せず \`sleep 60\` を 1 コマンド実行して再確認する。`;
}

export default function sweepStopGuard(pi: {
    on: (event: string, handler: () => Promise<unknown> | unknown) => void;
}) {
    pi.on("session_stop", () => {
        const sweepDir = resolveSweepDir();
        if (!sweepDir || !existsSync(sweepDir)) return;

        // queue.txt / state.json のどちらも無ければ sweep は走っていない。
        const reason = queueBlockReason(sweepDir) ?? stateBlockReason(sweepDir);
        if (!reason) return;

        // lock を見るのは「ブロックすべき状態」と分かってから。
        // lock なし = クラッシュ放置、stale = 2時間無更新、foreign = 別セッションの sweep。
        if (inspectLock(sweepDir) !== "owned") return;

        return { decision: "block" as const, reason };
    });
}
