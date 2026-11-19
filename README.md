# RollCall — the daily Agent ID roll call

Every agent, present. RollCall is a daily on-chain check-in ritual exclusively for
**Agent ID** holders on BNB Chain, built for the Binance Wallet × BNB Chain
Agent ID Hackathon.

If your wallet holds an Agent ID (the `name.ai` identity of an Agentic Wallet),
you can answer the roll call once per UTC day. Consecutive days build a streak.
You can also wave at any agent who is present today. The contract keeps a public
roll of registered agents, a per-day presence counter, streaks, and waves —
counters only.

## Why Agent ID is essential

Agent ID is one-per-person and non-transferable, so a check-in is a person-grade
presence signal that cannot be farmed with throwaway wallets. Without the Agent ID
gate, the roll would be a meaningless counter. Every state-changing function
checks the caller's Agent ID holding live against the official contract.

- Agent ID contract (BNB Chain): `0x60b9262456de011f7d15a54cdd8c48baaa8b022f`
- RollCall contract: `0x64605f009a7b1a3084c31f93d3bbaa72d6c74809` (BSC mainnet, deployed 2026-11-19, tx `0xc935fd1a05d57658774e98e8d8a0ffb45d1f49b7ef4a066211ead30d29bf6845`); source verified on Sourcify (exact match, matchId 59511277)

## Owner permissions: NONE

This is a deliberate design choice, documented as the hackathon rules require:

- The contract has **no owner and no admin role**.
- There is **no** pause, upgrade, mint, tax, freeze, or withdraw function.
- The Agent ID contract address is set once in the constructor and is **immutable**.
- The contract is **non-payable**: it cannot receive, hold, or move BNB or tokens.
  It stores counters only. Streaks and waves have no monetary value, and nothing
  here promises any return, reward, or income.

## Layout

- `contracts/RollCall.sol` — the contract (MIT, Solidity 0.8.24)
- `test/` — Foundry tests (16 behavior tests + gas measurements) with a test-only
  mock of the Agent ID `balanceOf` interface
- `frontend/index.html` — static single-page dApp (no build step, no backend,
  standard injected-wallet connect; hostable on GitHub Pages)
- `DESIGN.md` — concept selection, scoring, red-line compliance checklist
- `DEPLOY-PLAN.md` — deployment, verification, hosting, and submission steps

## Local development

Foundry 1.3.6 is vendored under `tools/` in this workspace:

```bash
export PATH="$PWD/tools:$PATH"
forge test            # 16 tests
forge test --gas-report
```

## Safety notes for users

- The dApp never asks for a seed phrase, private key, API secret, or pairing code,
  and never requests token approvals.
- Every check-in/wave is a normal transaction you review and confirm in your own
  wallet. It costs BNB Chain network gas (paid to the network). The contract
  itself charges nothing.
