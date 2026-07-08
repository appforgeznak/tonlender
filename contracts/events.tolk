// ============================================
// Event emission helpers for P2P NFT Lending — LoanVault subset
// Events are external out messages for indexers
// ============================================

import "messages.tolk"

// Get current contract address
@pure
fun getContractAddress(): address
    asm "MYADDR";

// ============================================
// Generic event emitter
// External out message format (TL-B):
// ext_out_msg_info$11 src:MsgAddressInt dest:MsgAddressExt
//   created_lt:uint64 created_at:uint32
//   init:(Maybe ^StateInit) body:(Either X ^X)
// ============================================
fun emitEvent(body: cell) {
    // Build external out message
    // Format: ext_out_msg_info$11 (2 bits = 3)
    var msg = beginCell()
        .storeUint(3, 2)                      // ext_out_msg_info$11
        .storeAddress(getContractAddress())   // src:MsgAddressInt (our address)
        .storeUint(0, 2)                      // dest:addr_none$00
        .storeUint(0, 64)                     // created_lt (filled by validator)
        .storeUint(0, 32)                     // created_at (filled by validator)
        .storeUint(0, 1)                      // init: nothing$0
        .storeUint(1, 1)                      // body: right$1 (as ref)
        .storeRef(body)
        .endCell();

    // Send with mode 0 (regular) - external messages don't need gas
    sendRawMessage(msg, 0);
}

// ============================================
// Vault events
// ============================================
fun emitLoanActivated(
    queryId: int,
    borrower: address,
    lender: address,
    principal: int,
    interest: int,
    dueTs: int
) {
    // Split to avoid overflow
    var loanData = beginCell()
        .storeCoins(principal)
        .storeCoins(interest)
        .storeUint(dueTs, 32)
        .storeUint(blockchain.now(), 32)
        .endCell();

    var body = beginCell()
        .storeUint(EVT_LOAN_ACTIVATED, 32)
        .storeUint(queryId, 64)
        .storeAddress(getContractAddress())
        .storeAddress(borrower)
        .storeAddress(lender)
        .storeRef(loanData)
        .endCell();

    emitEvent(body);
}

fun emitLoanRepaid(
    queryId: int,
    borrower: address,
    lender: address,
    principal: int,
    interest: int,
    vaultIncomingMsgValue: int,
    repayEscrowPayoutValue: int
) {
    // Split repay payload into a ref to avoid cell overflow on large values.
    var repayData = beginCell()
        .storeCoins(principal)
        .storeCoins(interest)
        .storeUint(blockchain.now(), 32)
        .storeCoins(vaultIncomingMsgValue)
        .storeCoins(repayEscrowPayoutValue)
        .endCell();

    var body = beginCell()
        .storeUint(EVT_LOAN_REPAID, 32)
        .storeUint(queryId, 64)
        .storeAddress(getContractAddress())
        .storeAddress(borrower)
        .storeAddress(lender)
        .storeRef(repayData)
        .endCell();

    emitEvent(body);
}

fun emitLoanDefaulted(
    queryId: int,
    borrower: address,
    lender: address,
    nftAddress: address,
    principal: int,
    vaultIncomingMsgValue: int
) {
    // Split to avoid overflow
    var defaultData = beginCell()
        .storeAddress(nftAddress)
        .storeCoins(principal)
        .storeUint(blockchain.now(), 32)
        .storeCoins(vaultIncomingMsgValue)
        .endCell();

    var body = beginCell()
        .storeUint(EVT_LOAN_DEFAULTED, 32)
        .storeUint(queryId, 64)
        .storeAddress(getContractAddress())
        .storeAddress(borrower)
        .storeAddress(lender)
        .storeRef(defaultData)
        .endCell();

    emitEvent(body);
}

fun emitLoanAborted(
    queryId: int,
    borrower: address,
    nftAddress: address,
    reason: int
) {
    var body = beginCell()
        .storeUint(EVT_LOAN_ABORTED, 32)
        .storeUint(queryId, 64)
        .storeAddress(getContractAddress())
        .storeAddress(borrower)
        .storeAddress(nftAddress)
        .storeUint(reason, 8)
        .storeUint(blockchain.now(), 32)
        .endCell();

    emitEvent(body);
}

fun emitNftReceived(
    queryId: int,
    nftAddress: address,
    prevOwner: address
) {
    var body = beginCell()
        .storeUint(EVT_NFT_RECEIVED, 32)
        .storeUint(queryId, 64)
        .storeAddress(getContractAddress())
        .storeAddress(nftAddress)
        .storeAddress(prevOwner)
        .storeUint(blockchain.now(), 32)
        .endCell();

    emitEvent(body);
}
