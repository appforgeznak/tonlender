// ============================================
// Storage structures for P2P NFT Lending — LoanVault
// ============================================
// This file contains ONLY the LoanVault storage layout — the other contracts'
// storage is not needed to work with a vault and is not part of this package.

// ============================================
// Loan status enum
// ============================================
const LOAN_STATUS_PENDING : int = 0
const LOAN_STATUS_ACTIVE : int = 1
const LOAN_STATUS_REPAID : int = 2
const LOAN_STATUS_DEFAULTED : int = 3
const LOAN_STATUS_ABORTED : int = 4

// ============================================
// LoanVault storage (split to avoid cell overflow)
// ============================================
// Participants stored as reference
struct VaultParticipants {
    borrower: address
    lender: address
    escrow: address
}

// NFT info stored as reference (contains participants ref)
struct VaultNftInfo {
    nftAddress: address
    nftCollection: address
    participants: cell // Cell<VaultParticipants>
}

// Main vault storage
struct VaultStorage {
    controller: address
    nftInfo: cell // Cell<VaultNftInfo>
    principal: coins
    interest: coins = 0        // max interest for full duration (set at activation)
    dueTs: uint32 = 0
    activatedAt: uint32 = 0    // timestamp when loan was activated (for pro-rata interest)
    status: uint8 = 0 // LOAN_STATUS_*
    nftReceived: bool = false
    nonce: uint64 = 0 // offer nonce - ensures unique Vault address per offer
}

fun VaultStorage.load(): VaultStorage {
    return VaultStorage.fromCell(contract.getData());
}

fun VaultStorage.save(self) {
    contract.setData(self.toCell());
}

// Helper to get NFT info
fun VaultStorage.getNftInfo(self): VaultNftInfo {
    return VaultNftInfo.fromCell(self.nftInfo);
}

// Helper to get participants
fun VaultStorage.getParticipants(self): VaultParticipants {
    var nftInfo = self.getNftInfo();
    return VaultParticipants.fromCell(nftInfo.participants);
}

// Helper to get NFT address
fun VaultStorage.getNftAddress(self): address {
    return self.getNftInfo().nftAddress;
}

// Helper to get NFT collection
fun VaultStorage.getNftCollection(self): address {
    return self.getNftInfo().nftCollection;
}
