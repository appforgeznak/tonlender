/**
 * Public operation and error codes for the TonLender `LoanVault` contract.
 *
 * These are the on-chain constants a client needs to build messages for a vault
 * and to interpret the exit codes / events it produces. They mirror the Tolk
 * sources in `contracts/` (`messages.tolk`, `errors.tolk`, `storage.tolk`) one to one.
 */

/**
 * Opcodes involved in the LoanVault lifecycle.
 *
 * `incoming` — messages the vault accepts.
 * `outgoing` — messages the vault sends to the NFT item / escrow / controller.
 */
export const LoanVaultOpcodes = {
    // ---- Incoming (sent TO the vault) ----
    /** TEP-62 `ownership_assigned` — the collateral NFT arrived at the vault. */
    nftOwnershipAssigned: 0x05138d91,
    /** Controller → vault: activate the loan (sets lender, dueTs, interest). */
    activate: 0x30000001,
    /** Borrower → vault: repay principal + pro-rata interest before `dueTs`. */
    repay: 0x30000002,
    /** Lender → vault: claim the collateral after `dueTs` on default. */
    claimDefault: 0x30000003,
    /** Controller → vault: abort a pending loan (reserve failed). */
    abort: 0x30000004,

    // ---- Outgoing (sent BY the vault) ----
    /** TEP-62 `transfer` — vault moves the NFT to borrower (repay) or lender (default). */
    nftTransfer: 0x5fcc3d14,
    /** Vault → controller: NFT received, proceed to verify offer + reserve. */
    vaultReceivedNft: 0x20000001,
    /** Vault → escrow: release reserved funds on repay. */
    escrowRelease: 0x10000005,
    /** Vault → escrow: release (bookkeeping only) on default. */
    escrowReleaseDefault: 0x10000009,
    /** Vault → controller: collect the 10% service fee (also carries event data). */
    collectServiceFee: 0x20000005,
    /** Vault → controller: internal "loan activated" index event. */
    vaultEventActivated: 0x20000010,
    /** Vault → controller: internal "loan aborted" index event. */
    vaultEventAborted: 0x20000013,
} as const;

/**
 * External-out message opcodes the vault emits for indexers (logs / events).
 */
export const LoanVaultEvents = {
    loanActivated: 0xe0000020,
    loanRepaid: 0xe0000021,
    loanDefaulted: 0xe0000022,
    loanAborted: 0xe0000023,
    nftReceived: 0xe0000024,
} as const;

/**
 * `reason` byte carried in the `collectServiceFee` payload.
 */
export const ServiceFeeReason = {
    repay: 1,
    default: 2,
} as const;

/**
 * Loan lifecycle status stored in the vault (`get_loan_status`).
 */
export const LoanStatus = {
    PENDING: 0,
    ACTIVE: 1,
    REPAID: 2,
    DEFAULTED: 3,
    ABORTED: 4,
} as const;

export type LoanStatusValue = (typeof LoanStatus)[keyof typeof LoanStatus];

/** Human-readable label for a numeric loan status. */
export const LOAN_STATUS_LABELS: Record<number, string> = {
    [LoanStatus.PENDING]: "pending",
    [LoanStatus.ACTIVE]: "active",
    [LoanStatus.REPAID]: "repaid",
    [LoanStatus.DEFAULTED]: "defaulted",
    [LoanStatus.ABORTED]: "aborted",
};

/**
 * Exit / error codes the vault can throw. Numbering follows the protocol-wide
 * ranges (100-199 general, 200-299 escrow-shared, 400-499 vault).
 */
export const LoanVaultErrors = {
    /** 101 — unknown opcode. */
    invalidOp: 101,
    /** 103 — attached message value below the required gas floor. */
    insufficientGas: 103,
    /** 106 — malformed forward payload (escrow address mismatch). */
    badData: 106,
    /** 204 — sender is not the controller (activate / abort). */
    onlyController: 204,
    /** 400 — operation requires an ACTIVE loan. */
    loanNotActive: 400,
    /** 401 — default claim before `dueTs` (loan not yet defaulted). */
    loanNotDefaulted: 401,
    /** 402 — loan already active / NFT already received. */
    loanAlreadyActive: 402,
    /** 403 — repay value below `principal + interest + gas floor`. */
    invalidRepayAmount: 403,
    /** 404 — repay sender is not the borrower. */
    notBorrower: 404,
    /** 405 — default claim sender is not the lender. */
    notLender: 405,
    /** 406 — activation attempted before the NFT was received. */
    nftNotReceived: 406,
    /** 407 — received NFT address does not match the expected collateral. */
    wrongNft: 407,
    /** 409 — repay attempted after `dueTs`. */
    loanOverdue: 409,
    /** 410 — attached service fee below the required amount (default). */
    invalidServiceFee: 410,
} as const;

/** Short English message for each vault error code (for UX / logging). */
export const LOAN_VAULT_ERROR_MESSAGES: Record<number, string> = {
    [LoanVaultErrors.invalidOp]: "Unknown operation",
    [LoanVaultErrors.insufficientGas]: "Insufficient gas attached",
    [LoanVaultErrors.badData]: "Malformed forward payload",
    [LoanVaultErrors.onlyController]: "Sender is not the controller",
    [LoanVaultErrors.loanNotActive]: "Loan is not active",
    [LoanVaultErrors.loanNotDefaulted]: "Loan is not defaulted yet",
    [LoanVaultErrors.loanAlreadyActive]: "Loan already active",
    [LoanVaultErrors.invalidRepayAmount]: "Repay amount too low",
    [LoanVaultErrors.notBorrower]: "Sender is not the borrower",
    [LoanVaultErrors.notLender]: "Sender is not the lender",
    [LoanVaultErrors.nftNotReceived]: "NFT collateral not received",
    [LoanVaultErrors.wrongNft]: "Unexpected NFT collateral",
    [LoanVaultErrors.loanOverdue]: "Loan is overdue",
    [LoanVaultErrors.invalidServiceFee]: "Service fee too low",
};
