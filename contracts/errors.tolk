// ============================================
// Error codes for P2P NFT Lending Protocol — LoanVault public subset
// ============================================
// Only the error codes that LoanVault (`throw` / `assert`) can raise are exposed
// here. Numbering follows the protocol-wide ranges (100-199 general, 200-299
// escrow-shared, 400-499 vault) so codes stay stable across the whole system.

// General errors (100-199)
const E_INVALID_OP : int = 101
const E_INSUFFICIENT_GAS : int = 103
const E_BAD_DATA = 106

// Escrow errors (200-299)
const E_ONLY_CONTROLLER : int = 204

// Vault errors (400-499)
const E_LOAN_NOT_ACTIVE : int = 400
const E_LOAN_NOT_DEFAULTED : int = 401
const E_LOAN_ALREADY_ACTIVE : int = 402
const E_INVALID_REPAY_AMOUNT : int = 403
const E_NOT_CONTROLLER : int = 404
const E_NOT_LENDER : int = 405
const E_NFT_NOT_RECEIVED : int = 406
const E_WRONG_NFT : int = 407
const E_LOAN_OVERDUE : int = 409
const E_INVALID_SERVICE_FEE : int = 410
