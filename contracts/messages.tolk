// ============================================
// Opcodes for P2P NFT Lending — LoanVault public subset
// ============================================
// This file exposes ONLY the opcodes involved in the LoanVault lifecycle
// (NFT transfer/ownership, activate/repay/claim/abort, the escrow-release and
// service-fee messages the Vault sends, and the Vault→Controller index events).
// The full protocol also defines Escrow- and Controller-internal opcodes; those
// are intentionally not part of this single-contract package.

// ============================================
// TEP-62 NFT Standard opcodes
// ============================================
const OP_NFT_TRANSFER : int = 0x5fcc3d14
const OP_NFT_OWNERSHIP_ASSIGNED : int = 0x05138d91

// ============================================
// LenderEscrow opcodes (sent by Vault)
// ============================================
const OP_ESCROW_RELEASE : int = 0x10000005
const OP_ESCROW_RELEASE_DEFAULT : int = 0x10000009

// ============================================
// LoanController opcodes (sent by Vault)
// ============================================
const OP_VAULT_RECEIVED_NFT : int = 0x20000001
const OP_CONTROLLER_COLLECT_SERVICE_FEE : int = 0x20000005 // Internal: from Vault to Controller
// Service fee reason codes (used in OP_CONTROLLER_COLLECT_SERVICE_FEE payload)
const SERVICE_FEE_REASON_REPAY : int = 1
const SERVICE_FEE_REASON_DEFAULT : int = 2
// Vault -> Controller internal events (for centralized indexing)
const OP_VAULT_EVENT_ACTIVATED : int = 0x20000010
const OP_VAULT_EVENT_ABORTED : int = 0x20000013

// ============================================
// LoanVault opcodes
// ============================================
const OP_VAULT_ACTIVATE : int = 0x30000001
const OP_VAULT_REPAY : int = 0x30000002
const OP_VAULT_CLAIM_DEFAULT : int = 0x30000003
const OP_VAULT_ABORT : int = 0x30000004

// ============================================
// Event opcodes (external out messages)
// ============================================
const EVT_LOAN_ACTIVATED : int = 0xe0000020
const EVT_LOAN_REPAID : int = 0xe0000021
const EVT_LOAN_DEFAULTED : int = 0xe0000022
const EVT_LOAN_ABORTED : int = 0xe0000023
const EVT_NFT_RECEIVED : int = 0xe0000024

// ============================================
// Internal message helpers
// ============================================
// Parse internal message info and return (flags, sender)
@pure
fun getInternalMsgInfo(msgFull: cell): (int, address) {
    var cs = msgFull.beginParse();
    var flags = cs.loadUint(4);
    var sender = cs.loadAddress();
    return (flags, sender);
}
