# LoanVault — Public API

Reference for the public API of `tonlender-sdk`: the TypeScript wrapper, the
on-chain contract interface (get-methods, accepted messages, emitted events),
and the constant tables.

- [TypeScript API](#typescript-api)
  - [Constructing a vault](#constructing-a-vault)
  - [Get-methods](#get-methods)
  - [Send-methods](#send-methods)
- [Contract API (on-chain)](#contract-api-on-chain)
  - [TVM get-methods](#tvm-get-methods)
  - [Accepted internal messages](#accepted-internal-messages)
  - [Emitted events](#emitted-events)
- [Constants](#constants)
  - [Opcodes](#opcodes)
  - [Events](#events)
  - [Loan status](#loan-status)
  - [Error / exit codes](#error--exit-codes)
- [Economics](#economics)

All amounts are in nanoton (`bigint`) unless stated otherwise. `1 TON = 1_000_000_000 nanoton`.

---

## TypeScript API

```ts
import {
  LoanVault,
  vaultConfigToCell,
  LoanVaultOpcodes,
  LoanVaultEvents,
  LoanVaultErrors,
  LOAN_VAULT_ERROR_MESSAGES,
  LoanStatus,
  LOAN_STATUS_LABELS,
  ServiceFeeReason,
} from "tonlender-sdk";
import type { VaultConfig } from "tonlender-sdk";
```

`@ton/core` is a peer dependency and provides `Address`, `Cell`, `Sender`,
`ContractProvider`, etc.

### Constructing a vault

Vaults are deployed by the `LoanController`, one per loan, at a deterministic
address. In practice you attach to an existing vault by address:

```ts
const vault = client.open(LoanVault.createFromAddress(Address.parse("EQ...")));
```

| Member | Signature | Notes |
| --- | --- | --- |
| `LoanVault.createFromAddress` | `(address: Address): LoanVault` | Attach to a deployed vault. Use this for reads and for `repay` / `claimDefault`. |
| `LoanVault.createFromConfig` | `(config: VaultConfig, code: Cell, workchain = 0): LoanVault` | Compute the address from init data + code and build a deployable instance. Mainly for tests / simulation — on mainnet the controller deploys the vault. |
| `new LoanVault` | `(address: Address, init?: { code, data })` | Low-level constructor. |
| `vaultConfigToCell` | `(config: VaultConfig): Cell` | Build the vault's initial storage cell from a config. |

**`VaultConfig`**

```ts
type VaultConfig = {
  controller: Address;   // LoanController that owns this vault
  nftAddress: Address;   // collateral NFT item
  nftCollection: Address;
  borrower: Address;
  lender?: Address;      // deprecated; ignored for address derivation (set on-chain at activation)
  escrow: Address;       // lender's LenderEscrow
  principal: bigint;     // loan principal, nanoton
  nonce?: bigint;        // makes the vault address unique per offer (default 0n)
};
```

### Get-methods

Each returns a `Promise`. Read them via a `ContractProvider` (e.g.
`client.open(vault).getLoanStatus()`).

| Method | Returns | Description |
| --- | --- | --- |
| `getLoanStatus()` | `number` | Loan status `0..4`, see [Loan status](#loan-status). |
| `getTotalDue()` | `bigint` | Amount owed now (nanoton). For an active loan = `principal + pro-rata interest`; otherwise `principal + interest`. |
| `isDefaulted()` | `boolean` | `true` when the loan is active **and** past its deadline (claimable by the lender). |
| `getTimeRemaining()` | `number` | Seconds until the deadline; `0` if not active or already past due. |
| `getNftAddress()` | `Address` | The collateral NFT item address. |
| `getPrincipal()` | `bigint` | Loan principal (nanoton). |

### Send-methods

Each builds the message body and sends it through a `Sender` (`via`). The
`value` column is the TON that must be attached.

| Method | Attached value | Who / when | Body |
| --- | --- | --- | --- |
| `sendDeploy(provider, via, value)` | caller-chosen | deployer | empty |
| `sendActivate(provider, via, opts)` | `0.05 TON` | controller only, on a pending vault | `activate` |
| `sendRepay(provider, via, opts)` | `opts.value` ≥ `totalDue + 0.025 TON` | borrower, before deadline | `repay` |
| `sendClaimDefault(provider, via, opts)` | `opts.value` ≥ `0.05 TON + service fee` | lender, after deadline | `claim_default` |
| `sendAbort(provider, via, opts)` | `0.05 TON` | controller only, on a pending vault | `abort` |
| `sendNftOwnershipAssigned(provider, via, opts)` | `0.5 TON` | test helper — simulate NFT arrival | `ownership_assigned` |

Options:

```ts
sendActivate(provider, via, {
  lender: Address;
  dueTs: number;     // unix seconds — loan deadline
  interest: bigint;  // max interest for the full term, nanoton
  queryId?: bigint;
});

sendRepay(provider, via, {
  value: bigint;     // >= totalDue + 0.025 TON
  queryId?: bigint;
});

sendClaimDefault(provider, via, {
  value: bigint;     // >= 0.05 TON + serviceFee(=10% of full-term interest)
  queryId?: bigint;
});

sendAbort(provider, via, { queryId?: bigint });

sendNftOwnershipAssigned(provider, via, {
  prevOwner: Address;
  forwardPayload?: Cell;
  queryId?: bigint;
});
```

> `sendActivate` / `sendAbort` are controller-only on-chain (the contract asserts
> the sender is the controller). They are exposed for tests and integrations that
> drive the full flow; end users only ever call `sendRepay` / `sendClaimDefault`.

**Examples**

```ts
// Borrower repays before the deadline
const totalDue = await vault.getTotalDue();
await vault.sendRepay(sender, { value: totalDue + toNano("0.05") });

// Lender claims the collateral after default
await vault.sendClaimDefault(sender, { value: toNano("0.1") });
```

---

## Contract API (on-chain)

### TVM get-methods

| Get-method | Return | Meaning |
| --- | --- | --- |
| `get_loan_status` | `int` | Loan status `0..4`. |
| `get_total_due` | `int` | Amount owed now (nanoton). |
| `is_defaulted` | `int` (bool) | `-1` if active and past deadline, else `0`. |
| `get_time_remaining` | `int` | Seconds to deadline, `0` if not active/overdue. |
| `get_nft_address` | `slice` (address) | Collateral NFT item. |
| `get_principal` | `int` | Loan principal (nanoton). |

### Accepted internal messages

TL-B of the message bodies the vault accepts:

```tlb
// TEP-62: the collateral NFT notifies the vault it was received
ownership_assigned#05138d91 query_id:uint64 prev_owner:MsgAddress
    forward_payload:(Either Cell ^Cell) = InternalMsgBody;

// Controller → vault: activate the loan
activate#30000001 query_id:uint64 lender:MsgAddress
    due_ts:uint32 interest:(VarUInteger 16) = InternalMsgBody;

// Borrower → vault: repay (before due_ts)
repay#30000002 query_id:uint64 = InternalMsgBody;

// Lender → vault: claim collateral (after due_ts)
claim_default#30000003 query_id:uint64 = InternalMsgBody;

// Controller → vault: abort a pending loan
abort#30000004 query_id:uint64 = InternalMsgBody;
```

| Message | Sender | Preconditions | Effect |
| --- | --- | --- | --- |
| `ownership_assigned` | NFT item | NFT not yet received, address matches, `prev_owner = controller` | Marks collateral received, notifies the controller. A stray NFT from a non-controller sender is returned. |
| `activate` | controller | status `PENDING`, NFT received | `PENDING → ACTIVE`; stores lender, `due_ts`, interest. |
| `repay` | borrower | status `ACTIVE`, `now ≤ due_ts`, `value ≥ principal + interest + 0.025 TON` | `ACTIVE → REPAID`; releases funds to escrow, returns NFT to borrower, refunds overpayment, collects the service fee. |
| `claim_default` | lender | status `ACTIVE`, `now > due_ts`, `value ≥ 0.05 TON + service fee` | `ACTIVE → DEFAULTED`; transfers NFT to lender, notifies escrow. |
| `abort` | controller | status `PENDING` | `PENDING → ABORTED`; returns NFT to borrower if held. |

The `forward_payload` on `ownership_assigned` carries the loan offer (first ref)
and the escrow address; the vault only checks the escrow and forwards the rest to
the controller for validation.

### Emitted events

The vault emits external-out messages (logs) for indexers. Body starts with the
event opcode + `query_id`; see [Events](#events).

| Event | Emitted when |
| --- | --- |
| `nftReceived` | Collateral NFT accepted. |
| `loanActivated` | Loan moved to `ACTIVE`. |
| `loanRepaid` | Loan repaid. |
| `loanDefaulted` | Collateral claimed on default. |
| `loanAborted` | Pending loan aborted. |

---

## Constants

### Opcodes

`LoanVaultOpcodes`:

| Name | Value | Direction |
| --- | --- | --- |
| `nftOwnershipAssigned` | `0x05138d91` | in (from NFT) |
| `activate` | `0x30000001` | in (from controller) |
| `repay` | `0x30000002` | in (from borrower) |
| `claimDefault` | `0x30000003` | in (from lender) |
| `abort` | `0x30000004` | in (from controller) |
| `nftTransfer` | `0x5fcc3d14` | out → NFT item |
| `vaultReceivedNft` | `0x20000001` | out → controller |
| `escrowRelease` | `0x10000005` | out → escrow (repay) |
| `escrowReleaseDefault` | `0x10000009` | out → escrow (default) |
| `collectServiceFee` | `0x20000005` | out → controller |
| `vaultEventActivated` | `0x20000010` | out → controller |
| `vaultEventAborted` | `0x20000013` | out → controller |

### Events

`LoanVaultEvents`:

| Name | Value |
| --- | --- |
| `loanActivated` | `0xe0000020` |
| `loanRepaid` | `0xe0000021` |
| `loanDefaulted` | `0xe0000022` |
| `loanAborted` | `0xe0000023` |
| `nftReceived` | `0xe0000024` |

### Loan status

`LoanStatus` / `LOAN_STATUS_LABELS`:

| Value | Name | Label |
| --- | --- | --- |
| `0` | `PENDING` | pending |
| `1` | `ACTIVE` | active |
| `2` | `REPAID` | repaid |
| `3` | `DEFAULTED` | defaulted |
| `4` | `ABORTED` | aborted |

`ServiceFeeReason`: `repay = 1`, `default = 2`.

### Error / exit codes

`LoanVaultErrors` / `LOAN_VAULT_ERROR_MESSAGES` — exit codes the vault can throw:

| Code | Name | Meaning |
| --- | --- | --- |
| `101` | `invalidOp` | Unknown operation. |
| `103` | `insufficientGas` | Attached value below the required gas floor. |
| `106` | `badData` | Malformed forward payload (escrow mismatch). |
| `204` | `onlyController` | Sender is not the controller (activate / abort). |
| `400` | `loanNotActive` | Operation requires an active loan. |
| `401` | `loanNotDefaulted` | Default claim before the deadline. |
| `402` | `loanAlreadyActive` | Loan already active / NFT already received. |
| `403` | `invalidRepayAmount` | Repay value below `principal + interest + gas floor`. |
| `404` | `notBorrower` | Repay sender is not the borrower. |
| `405` | `notLender` | Default-claim sender is not the lender. |
| `406` | `nftNotReceived` | Activation attempted before the NFT arrived. |
| `407` | `wrongNft` | Received NFT is not the expected collateral. |
| `409` | `loanOverdue` | Repay attempted after the deadline. |
| `410` | `invalidServiceFee` | Attached service fee too low (default). |

---

## Economics

- **Interest is pro-rata.** On repay the borrower pays
  `actualInterest = maxInterest × elapsed / fullDuration`, with a minimum charge
  of one day and a cap at `maxInterest`.
- **Total due** = `principal + actualInterest`.
- **Service fee = 10% of interest**, taken out of the interest (the lender
  receives `principal + 90% of interest`). The borrower does not pay it on top.
- **Repay gas floor**: the borrower attaches at least `0.025 TON` above
  `totalDue`; over-floor overpayment is refunded.
- **Default**: the lender attaches `0.05 TON` base + a service fee computed on the
  **full-term** interest (`10%`). On default the lender receives the NFT as the
  sole compensation — the principal is **not** returned (it was already disbursed
  to the borrower).
