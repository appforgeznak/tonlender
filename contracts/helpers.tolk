// ============================================
// Helpers (shared message builders/senders) — LoanVault subset
// ============================================
import "messages.tolk"

// ============================================
// NFT send cost — one canonical figure for moving an NFT. NFT_SEND_COST is the accounting cost
// of a transfer; NFT_SEND_ATTACH is what a contract attaches when it actually sends an NFT
// (cost + a small safety margin). Any excess parks on the NFT item, so it is not lost.
// ============================================
const NFT_SEND_COST   : int = 5000000   // 0.005 TON — accounting cost of ONE NFT transfer
const NFT_SEND_MARGIN : int = 5000000   // 0.005 TON — safety buffer added to the ATTACHED value
const NFT_SEND_ATTACH : int = NFT_SEND_COST + NFT_SEND_MARGIN  // 0.01 TON — value attached on every NFT send

// Return an NFT to its sender, carrying the REMAINING inbound message value (msgValue minus this
// tx's gas) to the NFT item via send mode 64; the item relays it to the sender's wallet
// (response_destination -> excesses). The contract's own balance is never touched; gas and
// forwarding are auto-deducted from the carried remainder.
fun returnNftRefundCarry(nftAddress: address, borrower: address, queryId: int) {
    var body = beginCell()
        .storeUint(OP_NFT_TRANSFER, 32)
        .storeUint(queryId, 64)
        .storeAddress(borrower)   // new_owner = borrower
        .storeAddress(borrower)   // response_destination = borrower -> leftover TON to wallet (excesses)
        .storeUint(0, 1)          // no custom_payload
        .storeCoins(1)            // forward_amount = 1 nanoton
        .storeUint(0, 1)          // no forward_payload
        .endCell();
    var msg = createMessage({
        bounce: BounceMode.Only256BitsOfBody,
        value: 0,
        dest: nftAddress,
        body,
    });
    msg.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
}
