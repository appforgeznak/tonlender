// ============================================
// LoanVault — holds NFT as collateral for a loan
// One vault per loan (deployed by the LoanController)
// ============================================
import "errors.tolk"
import "events.tolk"
import "helpers.tolk"
import "messages.tolk"
import "storage.tolk"

// ============================================
// Constants
// ============================================
// Gas/value constants for the vault's onward messages.
// NFT sends use the shared NFT_SEND_ATTACH (see helpers.tolk).
const SERVICE_FEE_RATE : int = 1000 // 10% = 1000 basis points (100 = 1%)
const MIN_SERVICE_FEE_MSG_VALUE : int = 30000000 // 0.03 TON controller gas (carried via CARRY_ALL)
const MIN_DEFAULT_CLAIM_MSG_VALUE : int = 50000000 // 0.05 TON gas floor the lender attaches for default claim (self-funded)
const REPAY_GAS_FLOOR : int = 25000000 // 0.025 TON borrower attaches on top of totalDue to self-fund NFT return + gas
const REPAY_REFUND_DUST : int = 3000000 // 0.003 TON — below this, skip the over-floor refund (not worth the fwd fee)
const GAS_FOR_CONTROLLER_OP : coins = 12000000 // 0.012 TON for controller gas
const GAS_FOR_ESCROW_OP : coins = 12000000 // 0.012 TON for escrow gas (default release)
const GAS_FOR_CONTROLLER_EVENT : coins = 12000000 // 0.012 TON for controller event

// ============================================
// Abort reason codes (for forward_payload on NFT return)
// ============================================
const ABORT_REASON_RESERVE_FAIL : int = 1
const ABORT_FWD_MAGIC : int = 0x41425254 // "ABRT"

// ============================================
// Internal message handler
// ============================================
fun onInternalMessage(myBalance: int, msgValue: int, msgFull: cell, msgBody: slice) {
    // Parse message info to detect bounces and sender (for NFT notifications)
    var (flags, sender) = getInternalMsgInfo(msgFull);
    if (flags & 1) {
        // Bounced — handle NFT transfer bounce
        onBounce(msgBody);
        return;
    }

    if (msgBody.isEmpty()) {
        return;
    }
    var body = msgBody;
    var op = body.loadUint(32);
    var queryId = body.loadUint(64);
    // For NFT notifications, the next field is previous owner address
    var storage = VaultStorage.load();
    var participants = storage.getParticipants();

    if (op == OP_NFT_OWNERSHIP_ASSIGNED) {
        // In standard NFT (TEP-62) ownership_assigned:
        // body layout for new owner:
        // op (32) | query_id (64) | prev_owner (address) | forward_payload (maybe ref)
        // At this point, body already has op and query_id consumed.
        // Next we load prev_owner and then parse forward_payload.
        // Step 1: load prev_owner (borrower address) right after op + query_id
        var prevOwner = body.loadAddress();
        var forwardPayload: slice;

        // Step 2: parse forward_payload as Maybe<Cell>
        // Layout now: forward_payload = hasRef (1 bit) | [ref cell if hasRef==1]
        // If there is no more data, treat as empty forward payload
        if (body.isEmpty()) {
            forwardPayload = beginCell().endCell().beginParse();
        } else {
            // Standard NFT path: forward_payload stored as Maybe<Cell> (storeMaybeRef)
            // Legacy path: some non-standard NFTs store forward_payload directly as a slice
            var bodyCopy = body;
            try {
                // Step 2.1: read hasRef flag (1 bit) from Maybe<Cell>
                var hasRef = bodyCopy.loadUint(1);
                if (hasRef == 1) {
                    // Standard NFT: next is ref to forwardPayload cell
                    var forwardPayloadRef = bodyCopy.loadRef();
                    forwardPayload = forwardPayloadRef.beginParse();
                } else {
                    // No forward payload present
                    forwardPayload = beginCell().endCell().beginParse();
                }
            } catch {
                // Fallback: assume the legacy format where body already IS the forward_payload slice
                forwardPayload = body;
            }
        }

        // Step 3: the forward payload carries the loan offer as its first ref.
        // Re-wrap the slice into a cell so it can be re-parsed cleanly below.
        var forwardPayloadCell = beginCell().storeSlice(forwardPayload).endCell();
        var payloadSliceCopy = forwardPayloadCell.beginParse();

        // Step 3.1: extract the offer ref
        var offerCell = payloadSliceCopy.loadRef();

        // Step 4: restore forwardPayload slice from cell for passing to onNftReceived/sendToController
        forwardPayload = forwardPayloadCell.beginParse();

        // sender (from msgFull) is NFT item address, prevOwner is borrower address
        onNftReceived(storage, participants, sender, prevOwner, forwardPayload, queryId, msgValue);
        return;
    }
    // Activate loan (from Controller after successful reserve+disburse)
    if (op == OP_VAULT_ACTIVATE) {
        assert(sender == storage.controller, E_ONLY_CONTROLLER);
        var lender = body.loadAddress();
        var dueTs = body.loadUint(32);
        var interest = body.loadCoins();
        activate(storage, lender, dueTs, interest, queryId);
        return;
    }

    // Repay loan (from Borrower)
    if (op == OP_VAULT_REPAY) {
        repay(storage, participants, sender, msgValue, queryId, myBalance);
        return;
    }

    // Claim defaulted loan (from Lender)
    if (op == OP_VAULT_CLAIM_DEFAULT) {
        claimDefault(storage, participants, sender, queryId, msgValue, myBalance);
        return;
    }

    // Abort loan (from Controller on reserve fail)
    if (op == OP_VAULT_ABORT) {
        assert(sender == storage.controller, E_ONLY_CONTROLLER);
        abortLoan(storage, participants, queryId);
        return;
    }

    throw E_INVALID_OP;
}

// ============================================
// NFT Received handler
// ============================================
fun onNftReceived(
    storage: VaultStorage,
    participants: VaultParticipants,
    nftAddress: address,
    prevOwner: address,
    forwardPayload: slice,
    queryId: int,
    msgValue: int,
) {
    // Vault accepts only ONE NFT

    assert(!storage.nftReceived, E_LOAN_ALREADY_ACTIVE);

    // Verify NFT address matches expected
    assert(nftAddress == storage.getNftAddress(), E_WRONG_NFT);

    if (prevOwner != storage.controller) {
        // Defensive: a stray NFT reached the vault from a non-controller sender. Return it to the
        // sender via carry-remaining, without touching the vault's own balance, regardless of msgValue.
        returnNftRefundCarry(nftAddress, prevOwner, queryId);
        return;
    }

    storage.nftReceived = true;
    storage.save();

    // Emit event
    emitNftReceived(queryId, nftAddress, prevOwner);

    // Forward to Controller to verify offer and initiate reserve
    sendToController(storage, participants, queryId, forwardPayload);
}

// ============================================
// Activate loan
// ============================================
fun activate(
    storage: VaultStorage,
    lender: address,
    dueTs: int,
    interest: int,
    queryId: int,
) {
    assert(storage.status == LOAN_STATUS_PENDING, E_LOAN_ALREADY_ACTIVE);
    assert(storage.nftReceived, E_NFT_NOT_RECEIVED);

    // Set the lender in participants (provided by the controller at activation)
    var nftInfo = storage.getNftInfo();
    var participants = VaultParticipants.fromCell(nftInfo.participants);
    var updatedParticipants = VaultParticipants {
        borrower: participants.borrower,
        lender,
        escrow: participants.escrow,
    };
    var updatedNftInfo = VaultNftInfo {
        nftAddress: nftInfo.nftAddress,
        nftCollection: nftInfo.nftCollection,
        participants: updatedParticipants.toCell(),
    };
    storage.nftInfo = updatedNftInfo.toCell();

    storage.status = LOAN_STATUS_ACTIVE;
    storage.dueTs = dueTs;
    storage.activatedAt = blockchain.now();
    storage.interest = interest;
    storage.save();

    // Emit event
    emitLoanActivated(
        queryId,
        updatedParticipants.borrower,
        updatedParticipants.lender,
        storage.principal,
        interest,
        dueTs
    );
    sendVaultEventActivated(
        storage.controller,
        queryId,
        updatedParticipants.borrower,
        updatedParticipants.lender,
        storage.principal,
        interest,
        dueTs
    );
}

// ============================================
// Repay loan (pro-rata interest for early repayment)
// ============================================

// Minimum interest charge = 1 day in seconds
const MIN_INTEREST_SECONDS : int = 86400

// Calculate pro-rata interest based on actual elapsed time since activation.
// actualInterest = maxInterest * elapsed / fullDuration
// Minimum charge = 1 day worth of interest; capped at maxInterest.
fun calcActualInterest(storage: VaultStorage): int {
    var fullDuration = storage.dueTs - storage.activatedAt;
    if (fullDuration <= 0) {
        return storage.interest; // safety: return full interest
    }
    var elapsed = blockchain.now() - storage.activatedAt;
    if (elapsed < MIN_INTEREST_SECONDS) {
        elapsed = MIN_INTEREST_SECONDS;
    }
    if (elapsed >= fullDuration) {
        return storage.interest;
    }
    return (storage.interest * elapsed) / fullDuration;
}

fun repay(
    storage: VaultStorage,
    participants: VaultParticipants,
    sender: address,
    msgValue: int,
    queryId: int,
    myBalance: int,
) {
    assert(storage.status == LOAN_STATUS_ACTIVE, E_LOAN_NOT_ACTIVE);
    assert(sender == participants.borrower, E_NOT_CONTROLLER);
    // Repayment allowed only before dueTs
    assert(blockchain.now() <= storage.dueTs, E_LOAN_OVERDUE);

    var actualInterest = calcActualInterest(storage);
    var totalDue = storage.principal + actualInterest;
    // Self-funded: borrower covers totalDue + a gas floor for the NFT return + onward sends,
    // so repay never depends on the vault's (storage-eroded) standing balance.
    assert(msgValue >= totalDue + REPAY_GAS_FLOOR, E_INVALID_REPAY_AMOUNT);

    // Store actual interest for event/distribution
    storage.interest = actualInterest;
    storage.status = LOAN_STATUS_REPAID;
    storage.save();

    // Same split as sendRepaymentToEscrow: principal + (interest minus protocol fee on interest)
    var serviceFee = (actualInterest * SERVICE_FEE_RATE) / 10000;
    var lenderInterestShare = actualInterest - serviceFee;
    var totalToEscrow = storage.principal + lenderInterestShare;

    // Emit event with actual interest paid + amounts for off-chain indexing
    emitLoanRepaid(
        queryId,
        participants.borrower,
        participants.lender,
        storage.principal,
        actualInterest,
        msgValue,
        totalToEscrow
    );

    // Send repayment to lender's escrow (release reserved funds + actual interest)
    sendRepaymentToEscrow(storage, participants, queryId, myBalance, msgValue);

    // Return NFT to borrower
    sendNftTo(storage.getNftAddress(), participants.borrower, queryId);

    // Refund the borrower's overpayment above the on-chain gas floor back to their wallet.
    // refund = msgValue − totalDue − REPAY_GAS_FLOOR (≥ 0 by the assert above). The gas floor
    // stays in the vault to fund the NFT return + onward sends. Skip dust amounts.
    var refund = msgValue - totalDue - REPAY_GAS_FLOOR;
    if (refund > REPAY_REFUND_DUST) {
        var refundMsg = createMessage({
            bounce: BounceMode.NoBounce,
            value: refund,
            dest: participants.borrower,
            body: beginCell().endCell(),
        });
        refundMsg.send(SEND_MODE_REGULAR);
    }

    // Send service fee LAST — SEND_MODE_CARRY_ALL_BALANCE drains the vault remainder
    // (10% of actualInterest + leftover gas) to the Controller.
    var eventDataCell = beginCell()
        .storeAddress(participants.borrower)
        .storeAddress(participants.lender)
        .storeCoins(storage.principal)
        .storeCoins(actualInterest)
        .storeCoins(msgValue)
        .storeCoins(totalToEscrow)
        .endCell();
    sendServiceFeeToController(
        storage.controller,
        serviceFee,
        queryId,
        SERVICE_FEE_REASON_REPAY,
        eventDataCell
    );
}

// ============================================
// Claim defaulted loan
// ============================================
fun claimDefault(
    storage: VaultStorage,
    participants: VaultParticipants,
    sender: address,
    queryId: int,
    msgValue: int,
    myBalance: int,
) {
    assert(storage.status == LOAN_STATUS_ACTIVE, E_LOAN_NOT_ACTIVE);
    assert(sender == participants.lender, E_NOT_LENDER);
    // Claim allowed only after dueTs
    assert(blockchain.now() > storage.dueTs, E_LOAN_NOT_DEFAULTED);

    // Lender attaches a gas floor + AT LEAST the required service fee on the default path.
    // Using '>=' (not '==') lets the lender attach extra to top up a storage-eroded vault,
    // so claimDefault never depends on the vault's standing balance and the collateral can
    // always be reclaimed. Surplus drains to the controller via CARRY_ALL_BALANCE below.
    var requiredServiceFee = (storage.interest * SERVICE_FEE_RATE) / 10000;
    assert (msgValue >= MIN_DEFAULT_CLAIM_MSG_VALUE) throw E_INSUFFICIENT_GAS;
    var providedServiceFee = msgValue - MIN_DEFAULT_CLAIM_MSG_VALUE;
    assert (providedServiceFee >= requiredServiceFee) throw E_INVALID_SERVICE_FEE;

    // Action-phase safety guard: ensure (standing balance + msgValue) covers all onward sends.
    // The lender's MIN_DEFAULT_CLAIM_MSG_VALUE + serviceFee covers this down to a near-zero
    // standing balance.
    var minOutValue = NFT_SEND_ATTACH + GAS_FOR_ESCROW_OP + GAS_FOR_CONTROLLER_EVENT +
        requiredServiceFee + MIN_SERVICE_FEE_MSG_VALUE;
    assert (myBalance >= minOutValue) throw E_INSUFFICIENT_GAS;

    storage.status = LOAN_STATUS_DEFAULTED;
    storage.save();

    // Emit event
    emitLoanDefaulted(
        queryId,
        participants.borrower,
        participants.lender,
        storage.getNftAddress(),
        storage.principal,
        msgValue
    );

    // Transfer NFT to lender
    sendNftTo(storage.getNftAddress(), participants.lender, queryId);

    // Notify escrow to release reserved funds
    sendDefaultToEscrow(storage, participants, queryId);

    // Collect service fee LAST — uses SEND_MODE_CARRY_ALL_BALANCE to drain vault
    // This merged message also carries event data for Controller to re-emit and cleanup vault
    var eventDataCell = beginCell()
        .storeAddress(participants.borrower)
        .storeAddress(participants.lender)
        .storeAddress(storage.getNftAddress())
        .storeCoins(storage.principal)
        .storeCoins(msgValue)
        .endCell();
    sendServiceFeeToController(
        storage.controller,
        providedServiceFee,
        queryId,
        SERVICE_FEE_REASON_DEFAULT,
        eventDataCell
    );
}

// ============================================
// Abort loan (reserve failed)
// ============================================
fun abortLoan(storage: VaultStorage, participants: VaultParticipants, queryId: int) {
    assert(storage.status == LOAN_STATUS_PENDING, E_LOAN_ALREADY_ACTIVE);

    storage.status = LOAN_STATUS_ABORTED;
    storage.save();

    // Emit event
    emitLoanAborted(
        queryId,
        participants.borrower,
        storage.getNftAddress(),
        ABORT_REASON_RESERVE_FAIL
    );
    sendVaultEventAborted(
        storage.controller,
        queryId,
        participants.borrower,
        storage.getNftAddress(),
        ABORT_REASON_RESERVE_FAIL
    );

    // Return NFT to borrower
    if (storage.nftReceived) {
        // On abort we pass the reason back to the borrower: attach a forward_payload and set
        // forward_amount > 0 so the NFT sends ownership_assigned (with payload) to the new owner.
        sendNftToWithAbortReason(
            storage.getNftAddress(),
            participants.borrower,
            queryId,
            ABORT_REASON_RESERVE_FAIL
        );
    }
}

// ============================================
// Bounce handler
// ============================================
fun onBounce(msgBody: slice) {
    // If NFT transfer bounced, the NFT was not transferred successfully
}

// ============================================
// Message senders
// ============================================
fun sendToController(
    storage: VaultStorage,
    participants: VaultParticipants,
    queryId: int,
    forwardPayload: slice,
) {
    // The forward payload starts with the offer ref followed by the escrow address.
    // The vault only checks the escrow here; the rest is validated by the controller.
    var payloadSlice = forwardPayload;
    payloadSlice.loadRef(); // skip the offer ref
    var escrowFromPayload = payloadSlice.loadAddress();
    assert (escrowFromPayload == participants.escrow) throw E_BAD_DATA;

    var bodyBuilder = beginCell();
    bodyBuilder.storeUint(OP_VAULT_RECEIVED_NFT, 32);
    bodyBuilder.storeUint(queryId, 64);
    var body = bodyBuilder.endCell();

    // Use high-level createMessage instead of manual sendRawMessage
    var outMsg = createMessage({
        bounce: BounceMode.Only256BitsOfBody,
        value: GAS_FOR_CONTROLLER_OP,
        dest: storage.controller,
        body,
    });
    outMsg.send(SEND_MODE_REGULAR);
}

fun sendNftTo(nftAddress: address, newOwner: address, queryId: int) {
    // NFT transfer message body
    var body = beginCell().storeUint(OP_NFT_TRANSFER, 32).storeUint(queryId, 64).storeAddress(newOwner) // new_owner
        .storeUint(0, 2) // response_destination: addr_none$00 (2 bits) to avoid excesses message
        .storeUint(0, 1) // no custom_payload
        .storeCoins(1)
        .storeUint(0, 1) // no forward_payload
        .endCell();

    var outMsg = createMessage({
        bounce: BounceMode.Only256BitsOfBody,
        value: NFT_SEND_ATTACH,
        dest: nftAddress,
        body,
    });
    outMsg.send(SEND_MODE_PAY_FEES_SEPARATELY);
}

// Abort variant: return the NFT with the abort reason attached in the forward_payload.
fun sendNftToWithAbortReason(nftAddress: address, newOwner: address, queryId: int, reason: int) {
    // forward_payload cell: magic(32) + reason(32) + query_id(64)
    var payload = beginCell().storeUint(ABORT_FWD_MAGIC, 32).storeUint(reason, 32).storeUint(
        queryId,
        64
    )
        .endCell();

    // NFT transfer message body
    // NOTE: Standard NFT sends ownership_assigned only if forward_amount > 0.
    var body = beginCell().storeUint(OP_NFT_TRANSFER, 32).storeUint(queryId, 64).storeAddress(newOwner) // new_owner
        .storeUint(0, 2) // response_destination: addr_none$00 (2 bits) to avoid excesses message
        .storeUint(0, 1) // no custom_payload
        .storeCoins(1) // forward_amount=1 nanoton: just to ensure ownership_assigned is delivered
        .storeUint(1, 1) // forward_payload: Maybe<Cell> = 1 bit + ref(cell)
        .storeRef(payload)
        .endCell();

    var outMsg = createMessage({
        bounce: BounceMode.Only256BitsOfBody,
        value: NFT_SEND_ATTACH,
        dest: nftAddress,
        body,
    });
    outMsg.send(SEND_MODE_REGULAR);
}

fun sendRepaymentToEscrow(
    storage: VaultStorage,
    participants: VaultParticipants,
    queryId: int,
    myBalance: int,
    msgValue: int,
) {
    // Calculate service fee (10% of interest)
    // SERVICE_FEE_RATE = 1000 basis points = 10%
    var serviceFee = (storage.interest * SERVICE_FEE_RATE) / 10000;
    var lenderInterest = storage.interest - serviceFee;

    var totalToEscrow = storage.principal + lenderInterest;

    var bodyRef = beginCell().storeCoins(storage.principal) // Principal amount to release
        .storeAddress(getContractAddress()) // vault address: allow Escrow to accept release from Vault
        .endCell();

    var body = beginCell().storeUint(OP_ESCROW_RELEASE, 32) // Opcode (32 bits)
        .storeUint(queryId, 64) // QueryId (64 bits)
        .storeUint(1, 1) // hasRef flag (1 bit) - indicates that principal and vaultAddress are in ref
        .storeRef(bodyRef) // ref to cell containing [principal (coins), vaultAddress (address)]
        .endCell();

    var outMsg = createMessage({
        bounce: BounceMode.Only256BitsOfBody,
        // Send principal + lender interest back to the escrow as real TON.
        value: totalToEscrow,
        dest: participants.escrow,
        body,
    });
    // Pay fees separately to deliver full msgValue to Escrow
    outMsg.send(SEND_MODE_PAY_FEES_SEPARATELY);

    // Service fee is sent separately from repay() after all other messages,
    // using SEND_MODE_CARRY_ALL_BALANCE to drain the vault.
}

fun sendDefaultToEscrow(storage: VaultStorage, participants: VaultParticipants, queryId: int) {
    // For default case, send release with principal in ref (same structure as repay)
    var bodyRef = beginCell().storeCoins(storage.principal).storeAddress(getContractAddress()) // vault address: allow Escrow to accept release from Vault
        .endCell();

    // Body must be inline (not ref) so Escrow can read opcode and queryId directly
    var body = beginCell().storeUint(OP_ESCROW_RELEASE_DEFAULT, 32).storeUint(queryId, 64).storeUint(1, 1) // bodyRef is ref
        .storeRef(bodyRef) // principal and vaultAddress in ref
        .endCell();

    var outMsg = createMessage({
        bounce: BounceMode.Only256BitsOfBody,
        value: GAS_FOR_ESCROW_OP, // Gas for default release notification
        dest: participants.escrow,
        body,
    });
    outMsg.send(SEND_MODE_REGULAR);
}

fun sendServiceFeeToController(controller: address, amount: int, queryId: int, reason: int, eventDataCell: cell) {
    var body = beginCell()
        .storeUint(OP_CONTROLLER_COLLECT_SERVICE_FEE, 32)
        .storeUint(queryId, 64)
        .storeUint(reason, 8)
        .storeRef(eventDataCell)
        .endCell();

    var sendValue = amount + MIN_SERVICE_FEE_MSG_VALUE;
    var outMsg = createMessage({
        bounce: BounceMode.Only256BitsOfBody,
        value: sendValue, // Service fee + min gas for Controller (msgValue)
        dest: controller,
        body,
    });
    outMsg.send(SEND_MODE_CARRY_ALL_BALANCE);
}

fun sendVaultEventActivated(
    controller: address,
    queryId: int,
    borrower: address,
    lender: address,
    principal: int,
    interest: int,
    dueTs: int
) {
    var body = beginCell()
        .storeUint(OP_VAULT_EVENT_ACTIVATED, 32)
        .storeUint(queryId, 64)
        .storeAddress(borrower)
        .storeAddress(lender)
        .storeCoins(principal)
        .storeCoins(interest)
        .storeUint(dueTs, 32)
        .endCell();

    var outMsg = createMessage({
        bounce: BounceMode.Only256BitsOfBody,
        value: GAS_FOR_CONTROLLER_EVENT,
        dest: controller,
        body,
    });
    outMsg.send(SEND_MODE_REGULAR);
}

fun sendVaultEventAborted(
    controller: address,
    queryId: int,
    borrower: address,
    nftAddress: address,
    reason: int
) {
    var body = beginCell()
        .storeUint(OP_VAULT_EVENT_ABORTED, 32)
        .storeUint(queryId, 64)
        .storeAddress(borrower)
        .storeAddress(nftAddress)
        .storeUint(reason, 8)
        .endCell();

    var outMsg = createMessage({
        bounce: BounceMode.Only256BitsOfBody,
        value: GAS_FOR_CONTROLLER_EVENT,
        dest: controller,
        body,
    });
    outMsg.send(SEND_MODE_REGULAR);
}

// ============================================
// Get methods
// ============================================
get fun get_loan_status(): int {
    return VaultStorage.load().status;
}

get fun get_total_due(): int {
    var s = VaultStorage.load();
    if (s.status != LOAN_STATUS_ACTIVE || s.activatedAt == 0) {
        return s.principal + s.interest;
    }
    return s.principal + calcActualInterest(s);
}

get fun is_defaulted(): bool {
    var s = VaultStorage.load();
    return s.status == LOAN_STATUS_ACTIVE && blockchain.now() > s.dueTs;
}

get fun get_time_remaining(): int {
    var s = VaultStorage.load();
    if (s.status != LOAN_STATUS_ACTIVE) {
        return 0;
    }
    var now = blockchain.now();
    if (now >= s.dueTs) {
        return 0;
    }
    return s.dueTs - now;
}

get fun get_nft_address(): address {
    return VaultStorage.load().getNftAddress();
}

get fun get_principal(): int {
    return VaultStorage.load().principal;
}
