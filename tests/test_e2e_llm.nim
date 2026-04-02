import std/[os, asyncdispatch, unittest, strutils]
import ../src/nimclaw/[config, providers/http, agent/loop, bus]

suite "E2E LLM Integration":
  test "OpenRouter + Claude 3.5 Sonnet":
    # 1. Setup Environment
    # Note: User provided this key for testing.
    putEnv("OPENROUTER_API_KEY", "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")
    putEnv("NIMCLAW_PROVIDER", "openrouter")
    putEnv("NIMCLAW_MODEL", "anthropic/claude-3.5-sonnet")

    # 2. Load Config with overrides
    var cfg = defaultConfig()
    cfg.parseEnv()
    cfg.agents.defaults.workspace = "/tmp/nimclaw_e2e_test"
    cfg.agents.defaults.max_tokens = 100
    
    # Ensure provider has the key (createProvider checks the config object)
    cfg.providers.openrouter.api_key = getEnv("OPENROUTER_API_KEY")
    
    # 3. Initialize Bus, Provider and Agent
    let msgBus = newMessageBus()
    let provider = createProvider(cfg)
    
    let agent = newAgentLoop(cfg, msgBus, provider)
    
    # 4. Execute a simple completion
    let prompt = "Please respond with exactly one word: PONG."
    echo "  -> Sending prompt to OpenRouter..."
    
    let result = waitFor agent.processDirect(prompt, "e2e:test")
    echo "  -> Received: ", result
    
    # 5. Verify response
    check result.toUpperAscii.contains("PONG")
    echo "  [OK] E2E verification successful"

    # Cleanup
    removeDir("/tmp/nimclaw_e2e_test")
