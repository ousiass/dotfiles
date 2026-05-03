package main

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"gopkg.in/yaml.v3"
)

type Provider struct {
	API       string `yaml:"api"`
	Model     string `yaml:"model"`
	BaseURL   string `yaml:"base_url,omitempty"`
	APIKeyEnv string `yaml:"api_key_env,omitempty"`
}

type Config struct {
	Providers map[string]Provider `yaml:"providers"`
	Default   string              `yaml:"default"`
}

var llmDir string

func init() {
	home, err := os.UserHomeDir()
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: ホームディレクトリを取得できません: %v\n", err)
		os.Exit(1)
	}
	llmDir = filepath.Join(home, ".claude", "llm")
}

func main() {
	if len(os.Args) < 2 {
		printUsage()
		os.Exit(1)
	}

	switch os.Args[1] {
	case "init":
		cmdInit()
	case "use":
		if len(os.Args) < 3 {
			fmt.Fprintln(os.Stderr, "error: プロバイダー名を指定してください")
			fmt.Fprintln(os.Stderr, "usage: swm use <name>")
			os.Exit(1)
		}
		cmdUse(os.Args[2])
	case "current":
		cmdCurrent()
	case "list":
		cmdList()
	case "env":
		cmdEnv()
	case "help", "--help", "-h":
		printUsage()
	default:
		fmt.Fprintf(os.Stderr, "error: 不明なコマンド: %s\n", os.Args[1])
		printUsage()
		os.Exit(1)
	}
}

func printUsage() {
	fmt.Println(`swm - LLMプロバイダー切り替えCLI

usage:
  swm init              providers.yaml のサンプルを生成
  swm use <name>        アクティブプロバイダーを切り替え
  swm current           現在のプロバイダーとモデルを表示
  swm list              全プロバイダー一覧
  swm env               環境変数を export 形式で出力`)
}

func configPath() string {
	return filepath.Join(llmDir, "providers.yaml")
}

func activePath() string {
	return filepath.Join(llmDir, "active")
}

func loadConfig() (*Config, error) {
	data, err := os.ReadFile(configPath())
	if err != nil {
		return nil, fmt.Errorf("providers.yaml を読み込めません: %w\n  `swm init` で初期化してください", err)
	}
	var cfg Config
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("providers.yaml のパースに失敗: %w", err)
	}
	return &cfg, nil
}

func activeProvider(cfg *Config) string {
	data, err := os.ReadFile(activePath())
	if err == nil {
		name := strings.TrimSpace(string(data))
		if _, ok := cfg.Providers[name]; ok {
			return name
		}
	}
	return cfg.Default
}

const defaultProvidersYAML = `providers:
  claude:
    api: anthropic
    model: claude-sonnet-4-5-20250929
    api_key_env: ANTHROPIC_API_KEY
  glm:
    api: openai
    model: glm-4
    base_url: https://open.bigmodel.cn/api/paas/v4
    api_key_env: ZHIPU_API_KEY
  deepseek:
    api: openai
    model: deepseek-chat
    base_url: https://api.deepseek.com
    api_key_env: DEEPSEEK_API_KEY
  local:
    api: openai
    model: llama3
    base_url: http://localhost:11434/v1
    api_key_env: ""

default: claude
`

func cmdInit() {
	if err := os.MkdirAll(llmDir, 0755); err != nil {
		fmt.Fprintf(os.Stderr, "error: ディレクトリの作成に失敗: %v\n", err)
		os.Exit(1)
	}

	path := configPath()
	if _, err := os.Stat(path); err == nil {
		fmt.Fprintf(os.Stderr, "providers.yaml は既に存在します: %s\n", path)
		os.Exit(1)
	}

	if err := os.WriteFile(path, []byte(defaultProvidersYAML), 0644); err != nil {
		fmt.Fprintf(os.Stderr, "error: ファイルの書き込みに失敗: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("作成しました: %s\n", path)
}

func cmdUse(name string) {
	cfg, err := loadConfig()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	if _, ok := cfg.Providers[name]; !ok {
		fmt.Fprintf(os.Stderr, "error: プロバイダー '%s' は定義されていません\n", name)
		fmt.Fprintln(os.Stderr, "利用可能なプロバイダー:")
		for k := range cfg.Providers {
			fmt.Fprintf(os.Stderr, "  - %s\n", k)
		}
		os.Exit(1)
	}

	if err := os.WriteFile(activePath(), []byte(name+"\n"), 0644); err != nil {
		fmt.Fprintf(os.Stderr, "error: active ファイルの書き込みに失敗: %v\n", err)
		os.Exit(1)
	}
	p := cfg.Providers[name]
	fmt.Printf("切り替えました: %s (%s)\n", name, p.Model)
}

func cmdCurrent() {
	cfg, err := loadConfig()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	name := activeProvider(cfg)
	p := cfg.Providers[name]
	fmt.Printf("%s (%s)\n", name, p.Model)
}

func cmdList() {
	cfg, err := loadConfig()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	active := activeProvider(cfg)

	names := make([]string, 0, len(cfg.Providers))
	for k := range cfg.Providers {
		names = append(names, k)
	}
	sort.Strings(names)

	for _, name := range names {
		p := cfg.Providers[name]
		marker := "  "
		if name == active {
			marker = "★ "
		}
		fmt.Printf("%s%s (%s)\n", marker, name, p.Model)
	}
}

func cmdEnv() {
	cfg, err := loadConfig()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	name := activeProvider(cfg)
	p := cfg.Providers[name]

	fmt.Printf("export LLM_PROVIDER=%s\n", name)
	fmt.Printf("export LLM_API=%s\n", p.API)
	fmt.Printf("export LLM_MODEL=%s\n", p.Model)

	if p.BaseURL != "" {
		fmt.Printf("export LLM_BASE_URL=%s\n", p.BaseURL)
	} else {
		fmt.Println("unset LLM_BASE_URL 2>/dev/null")
	}

	if p.APIKeyEnv != "" {
		val := os.Getenv(p.APIKeyEnv)
		if val != "" {
			fmt.Printf("export LLM_API_KEY=%s\n", val)
		} else {
			fmt.Fprintf(os.Stderr, "# warning: %s が設定されていません\n", p.APIKeyEnv)
			fmt.Println("unset LLM_API_KEY 2>/dev/null")
		}
	} else {
		fmt.Println("unset LLM_API_KEY 2>/dev/null")
	}
}
