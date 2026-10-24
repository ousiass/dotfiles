#!/usr/bin/env bash
# runner 本体の取得と登録（runner-host-setup.sh から source する。単体では実行しない）。
# 出所: このリポジトリ独自（上流の actions-runner-setup-base には無い）。
#
#   runner_asset_platform  : GitHub の actions/runner リリースの資産名に使う OS-CPU（osx-arm64 / linux-x64 など）
#   runner_default_labels  : 登録時に付けるラベル（macOS: self-hosted,macOS,ARM64 / Linux: self-hosted,linux,x64）
#   runner_gh_ready        : runner ユーザーの gh が使えて認証済みかを確かめる
#   runner_fetch           : 最新リリースを落とし、チェックサムを確かめて展開する
#   runner_install_deps    : Linux の runner の依存パッケージ（libicu など）を入れる
#   runner_register        : 登録トークンをその場で発行して config.sh で登録する
#
# 権限の分け方: このファイルの関数は root（sudo）で呼ばれる。root で動かすのは、ディレクトリを新しく作って
# 所有者を渡すところと、Linux の依存パッケージ（installdependencies.sh）だけ。ダウンロード・展開・gh・
# config.sh は runner ユーザーで実行する（config.sh は root を拒否する。gh の認証も runner ユーザーのもの）。
# 注意: Linux の installdependencies.sh は runner ユーザーが書き換えられる場所にあるスクリプトを root で
# 実行する。runner-host-setup.sh が同じ手順で NOPASSWD: ALL を入れるので新しい境界の突破ではないが、
# sudoers を絞るときはここも見直す（検証済み tarball から取り出すか、apt-get install で直接指定する）。
#
# 登録トークンの扱い: 1 時間で失効する秘密。gh のパイプから読み、config.sh の環境変数
# ACTIONS_RUNNER_INPUT_TOKEN（config.sh が --token の代わりに読む）にだけ渡す。コマンドライン引数・
# ファイル・ログに出さない（ps に載らない）。bash -c のスクリプトは定数で、トークンも他の値も埋め込まない
# （値は位置引数で渡すので、org / 名前 / group がシェルとして解釈されることもない）。gh のデバッグ出力
# （GH_DEBUG / DEBUG）は応答の本文を出しうるので、gh の実行では必ず外す。

# runner ユーザーとして実行する。cwd は / に固定する（呼び出し元の cwd を runner ユーザーが読めないと
# bash が警告を出すため。runner_exec と同じ）。
runner_as_user() {
	local user="$1"
	shift
	(cd / && sudo -u "$user" -H "$@")
}

# runner_asset_platform <OS> <machine> : 対応外なら何も出さず 1 を返す。
runner_asset_platform() {
	case "$1:$2" in
	Darwin:arm64) echo osx-arm64 ;;
	Linux:x86_64) echo linux-x64 ;;
	Linux:aarch64 | Linux:arm64) echo linux-arm64 ;;
	*) return 1 ;;
	esac
}

# runner_default_labels <OS> <machine> : 対応外なら何も出さず 1 を返す。
runner_default_labels() {
	case "$1:$2" in
	Darwin:arm64) echo "self-hosted,macOS,ARM64" ;;
	Linux:x86_64) echo "self-hosted,linux,x64" ;;
	Linux:aarch64 | Linux:arm64) echo "self-hosted,linux,arm64" ;;
	*) return 1 ;;
	esac
}

# runner_gh_ready <user> <gh> : gh が実行でき、runner ユーザーで認証済みなら 0。理由は標準エラーへ。
runner_gh_ready() {
	local user="$1" gh_bin="$2"
	if [ -z "$gh_bin" ] || [ ! -x "$gh_bin" ]; then
		echo "gh が見つかりません。runner 本体の取得と登録に使います。" >&2
		echo "  runner ユーザーで make runner-tools（sudo 不要）を実行して gh を入れ、gh auth login -s admin:org で認証してから、もう一度実行してください。" >&2
		return 1
	fi
	if ! runner_as_user "$user" env -u GH_DEBUG -u DEBUG "$gh_bin" auth status >/dev/null 2>&1; then
		echo "${user} の gh が未認証です。runner の登録に使います。" >&2
		echo "  ${user} で gh auth login -s admin:org を実行してから、もう一度実行してください。" >&2
		return 1
	fi
}

# runner_fetch <OS> <machine> <user> <dir> <gh>
runner_fetch() {
	local os="$1" machine="$2" user="$3" dir="$4" gh_bin="$5"
	local platform info name url digest

	if ! platform=$(runner_asset_platform "$os" "$machine"); then
		echo "対象外です: この OS / CPU の runner は取得できません: ${os} ${machine}" >&2
		return 1
	fi

	# 最新リリースの資産（名前・URL・sha256）。digest は GitHub が資産ごとに持つ値。
	if ! info=$(runner_as_user "$user" env -u GH_DEBUG -u DEBUG "$gh_bin" api repos/actions/runner/releases/latest \
		--jq ".assets[] | select(.name | test(\"^actions-runner-${platform}-[0-9.]+[.]tar[.]gz\$\")) | [.name, .browser_download_url, .digest] | @tsv"); then
		echo "actions/runner の最新リリースを取得できませんでした（${user} の gh のネットワーク・認証を確認）。" >&2
		return 1
	fi
	IFS=$'\t' read -r name url digest <<<"$info"
	if [ -z "$name" ] || [ -z "$url" ]; then
		echo "最新リリースに ${platform} の資産が見つかりません。" >&2
		return 1
	fi
	case "$url" in
	https://github.com/actions/runner/releases/download/*) ;;
	*)
		echo "想定外のダウンロード URL です: ${url}" >&2
		return 1
		;;
	esac
	# チェックサムが無いものは入れない（確かめずに展開しない）。
	case "$digest" in
	sha256:????????????????????????????????????????????????????????????????) digest="${digest#sha256:}" ;;
	*)
		echo "最新リリースの ${name} に sha256 の digest が無いため、取得を中止します。" >&2
		return 1
		;;
	esac

	# ディレクトリは無ければ作って所有者を渡す（親は作らない: root 所有の中間ディレクトリを残さない）。
	# 既にあるものの所有者は変えない（RUNNER_DIR の指定ミスで無関係なディレクトリを chown しない）。
	# 書き込めなければ止める。
	if [ ! -d "$dir" ]; then
		if [ ! -d "$(dirname "$dir")" ]; then
			echo "${dir} の親ディレクトリがありません。先に作るか、RUNNER_DIR で別の場所を指定してください。" >&2
			return 1
		fi
		mkdir "$dir"
		chown "$user" "$dir"
	elif ! runner_as_user "$user" test -w "$dir"; then
		echo "${dir} に ${user} が書き込めません。所有者を直すか、RUNNER_DIR で別の場所を指定してください。" >&2
		return 1
	fi

	echo "  取得: ${name}"
	runner_as_user "$user" bash -c '
set -euo pipefail
dir=$1 name=$2 url=$3 want=$4
marker="$dir/.runner-extracting"
# 前回 SIGKILL などで残った作業ディレクトリを片付ける。
rm -rf "$dir"/.fetch.*
stage=$(mktemp -d "$dir/.fetch.XXXXXX")
trap '\''rm -rf "$stage"'\'' EXIT
curl -fsSL --proto "=https" --tlsv1.2 --retry 3 --max-time 900 -o "$stage/$name" "$url"
if command -v sha256sum >/dev/null 2>&1; then got=$(sha256sum "$stage/$name"); else got=$(shasum -a 256 "$stage/$name"); fi
got=${got%% *}
if [ "$got" != "$want" ]; then
	echo "チェックサムが一致しません: ${name}（期待 ${want} / 実際 ${got}）" >&2
	exit 1
fi
mkdir "$stage/x"
tar -xzf "$stage/$name" -C "$stage/x"
for f in config.sh run.sh bin/Runner.Listener bin/runsvc.sh; do
	if [ ! -e "$stage/x/$f" ]; then
		echo "展開した runner に ${f} がありません（破損の疑い）" >&2
		exit 1
	fi
done
# 置き場所の確認。マーカー（.runner-extracting）は、この関数が展開を始めたときに置き、config.sh を置いた
# あとに消す。マーカーがあれば前回の途中で止まった残りなので、展開物と同名のものは置き換えてよい。
# マーカーが無いのに何かあれば、runner と無関係の中身なので、何も壊さず止まる。
resuming=0
[ -e "$marker" ] && resuming=1
for e in "$dir"/* "$dir"/.[!.]*; do
	[ -e "$e" ] || continue
	base=${e##*/}
	case "$base" in .fetch.* | .runner-extracting) continue ;; esac
	if [ "$resuming" -ne 1 ] || [ ! -e "$stage/x/$base" ]; then
		echo "空でないディレクトリには展開しません: ${dir}（${base} があります）。RUNNER_DIR で別の場所を指定するか、中身を片付けてください。" >&2
		exit 1
	fi
done
: >"$marker"
cd "$stage/x"
for e in * .[!.]*; do
	[ -e "$e" ] || continue
	[ "$e" = config.sh ] && continue
	rm -rf "${dir:?}/$e"
	mv -- "$e" "$dir/"
done
# config.sh は最後。在る = 展開が完了している（途中で止まっても「取得済み」と誤認しない）。
mv -- config.sh "$dir/"
rm -f "$marker"
' _ "$dir" "$name" "$url" "$digest" || return 1
	echo "  チェックサムを確認して ${dir} に展開した"
}

# runner_install_deps <OS> <dir> : Linux の runner の依存（.NET の libicu など）を apt で入れる。root で実行する。
# 冪等なので、未登録のときは毎回流す（前回 apt が失敗して止まっても、再実行で入る）。macOS は何もしない。
runner_install_deps() {
	local os="$1" dir="$2"
	[ "$os" = Linux ] || return 0
	if [ ! -f "$dir/bin/installdependencies.sh" ]; then
		echo "${dir}/bin/installdependencies.sh がありません。runner 本体が壊れています。" >&2
		return 1
	fi
	bash "$dir/bin/installdependencies.sh"
}

# runner_register <user> <dir> <org> <name> <group> <labels> <gh> <replace>
# replace=1 のときだけ --replace を付ける（同名の runner が org にあれば置き換える）。既定は付けない:
# RUNNER_DIR の指定ミスや 2 台目の登録で、稼働中の既存 runner を黙って追い出さないため。
runner_register() {
	local user="$1" dir="$2" org="$3" name="$4" group="$5" labels="$6" gh_bin="$7" replace="${8:-}"
	local replace_arg=""
	if [ -z "$labels" ]; then
		echo "ラベルを決められないため登録しません（この OS / CPU は対象外です）。" >&2
		return 1
	fi
	[ "$replace" = 1 ] && replace_arg=--replace
	echo "  登録: org=${org} name=${name} group=${group} labels=${labels}${replace_arg:+ ${replace_arg}}"
	# トークンは gh の出力をパイプで受けて config.sh の環境変数にだけ置く。
	if ! runner_as_user "$user" bash -c '
set -euo pipefail
dir=$1 org=$2 name=$3 group=$4 labels=$5 gh_bin=$6 replace_arg=$7
cd "$dir"
env -u GH_DEBUG -u DEBUG "$gh_bin" api -X POST "orgs/$org/actions/runners/registration-token" --jq .token | {
	IFS= read -r token || [ -n "$token" ]
	[ -n "$token" ] || exit 1
	ACTIONS_RUNNER_INPUT_TOKEN=$token ./config.sh --unattended ${replace_arg:+"$replace_arg"} \
		--url "https://github.com/$org" --name "$name" --runnergroup "$group" \
		--no-default-labels --labels "$labels" --work _work
}
' _ "$dir" "$org" "$name" "$group" "$labels" "$gh_bin" "$replace_arg"; then
		echo "runner の登録に失敗しました。次を確認してください。" >&2
		echo "  - ${user} の gh が org ${org} の admin:org 権限で認証済みか（gh auth status）" >&2
		echo "  - 同名の runner（${name}）が org に既にあるか。意図した置き換えなら RUNNER_REPLACE=1 を付けて再実行" >&2
		return 1
	fi
	echo "  登録した（ラベル: ${labels}）"
}
