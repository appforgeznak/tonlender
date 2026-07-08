import {
    Address,
    beginCell,
    Cell,
    Contract,
    contractAddress,
    ContractProvider,
    Sender,
    SendMode,
    toNano,
} from "@ton/core";
import { LoanVaultOpcodes, LoanStatus } from "./codes";

export type VaultConfig = {
    controller: Address;
    nftAddress: Address;
    nftCollection: Address;
    borrower: Address;
    lender?: Address; // deprecated, ignored for address derivation
    escrow: Address;
    principal: bigint;
    nonce?: bigint; // Optional for backward compatibility, but should be set for unique addresses
};

export function vaultConfigToCell(config: VaultConfig): Cell {
    // Participants cell
    const participantsCell = beginCell()
        .storeAddress(config.borrower)
        .storeAddress(config.controller) // placeholder lender (set on-chain on activate)
        .storeAddress(config.escrow)
        .endCell();

    // NFT info cell (to avoid overflow in main cell)
    const nftInfoCell = beginCell()
        .storeAddress(config.nftAddress)
        .storeAddress(config.nftCollection)
        .storeRef(participantsCell)
        .endCell();

    // Main storage: controller, nftInfo(ref), principal, interest, dueTs, activatedAt, status, nftReceived, nonce
    return beginCell()
        .storeAddress(config.controller)
        .storeRef(nftInfoCell)
        .storeCoins(config.principal)
        .storeCoins(0)                       // interest (max, set on activate)
        .storeUint(0, 32)                    // dueTs
        .storeUint(0, 32)                    // activatedAt
        .storeUint(0, 8)                     // status = PENDING
        .storeBit(false)                     // nft_received
        .storeUint(config.nonce ?? 0n, 64)   // nonce
        .endCell();
}

/**
 * Blueprint-style wrapper for the TonLender `LoanVault` contract.
 *
 * One vault is deployed per loan by the LoanController; it holds the collateral
 * NFT and drives the loan lifecycle: pending → active → repaid / defaulted / aborted.
 */
export class LoanVault implements Contract {
    constructor(
        readonly address: Address,
        readonly init?: { code: Cell; data: Cell }
    ) {}

    static createFromAddress(address: Address) {
        return new LoanVault(address);
    }

    static createFromConfig(config: VaultConfig, code: Cell, workchain = 0) {
        const data = vaultConfigToCell(config);
        const init = { code, data };
        return new LoanVault(contractAddress(workchain, init), init);
    }

    async sendDeploy(provider: ContractProvider, via: Sender, value: bigint) {
        await provider.internal(via, {
            value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: beginCell().endCell(),
        });
    }

    async sendActivate(
        provider: ContractProvider,
        via: Sender,
        opts: {
            lender: Address;
            dueTs: number;
            interest: bigint;
            queryId?: bigint;
        }
    ) {
        await provider.internal(via, {
            value: toNano("0.05"),
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: beginCell()
                .storeUint(LoanVaultOpcodes.activate, 32)
                .storeUint(opts.queryId ?? 0n, 64)
                .storeAddress(opts.lender)
                .storeUint(opts.dueTs, 32)
                .storeCoins(opts.interest)
                .endCell(),
        });
    }

    async sendRepay(
        provider: ContractProvider,
        via: Sender,
        opts: {
            value: bigint;
            queryId?: bigint;
        }
    ) {
        await provider.internal(via, {
            value: opts.value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: beginCell()
                .storeUint(LoanVaultOpcodes.repay, 32)
                .storeUint(opts.queryId ?? 0n, 64)
                .endCell(),
        });
    }

    async sendClaimDefault(
        provider: ContractProvider,
        via: Sender,
        opts: {
            queryId?: bigint;
            value: bigint;
        }
    ) {
        await provider.internal(via, {
            value: opts.value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: beginCell()
                .storeUint(LoanVaultOpcodes.claimDefault, 32)
                .storeUint(opts.queryId ?? 0n, 64)
                .endCell(),
        });
    }

    async sendAbort(
        provider: ContractProvider,
        via: Sender,
        opts: {
            queryId?: bigint;
        }
    ) {
        await provider.internal(via, {
            value: toNano("0.05"),
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: beginCell()
                .storeUint(LoanVaultOpcodes.abort, 32)
                .storeUint(opts.queryId ?? 0n, 64)
                .endCell(),
        });
    }

    /** Simulate a TEP-62 NFT transfer to the vault (mainly for tests). */
    async sendNftOwnershipAssigned(
        provider: ContractProvider,
        via: Sender,
        opts: {
            prevOwner: Address;
            forwardPayload?: Cell;
            queryId?: bigint;
        }
    ) {
        const body = beginCell()
            .storeUint(LoanVaultOpcodes.nftOwnershipAssigned, 32)
            .storeUint(opts.queryId ?? 0n, 64)
            .storeAddress(opts.prevOwner);

        if (opts.forwardPayload) {
            body.storeSlice(opts.forwardPayload.beginParse());
        }

        await provider.internal(via, {
            value: toNano("0.5"),
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: body.endCell(),
        });
    }

    async getLoanStatus(provider: ContractProvider) {
        const result = await provider.get("get_loan_status", []);
        return Number(result.stack.readBigNumber());
    }

    async getTotalDue(provider: ContractProvider) {
        const result = await provider.get("get_total_due", []);
        return result.stack.readBigNumber();
    }

    async isDefaulted(provider: ContractProvider) {
        const result = await provider.get("is_defaulted", []);
        return result.stack.readBoolean();
    }

    async getTimeRemaining(provider: ContractProvider) {
        const result = await provider.get("get_time_remaining", []);
        return Number(result.stack.readBigNumber());
    }

    async getNftAddress(provider: ContractProvider) {
        const result = await provider.get("get_nft_address", []);
        return result.stack.readAddress();
    }

    async getPrincipal(provider: ContractProvider) {
        const result = await provider.get("get_principal", []);
        return result.stack.readBigNumber();
    }
}

// Re-export lifecycle constants used by the wrapper for convenience.
export { LoanVaultOpcodes, LoanStatus };
