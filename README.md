# TonLender

## English

TonLender is a P2P lending protocol on the TON blockchain where borrowers can receive **GRAM** against NFT collateral, and lenders can provide **GRAM** on their own terms.

## What The Product Does

TonLender connects two sides of the market:

- **Borrowers** use NFTs as collateral and access liquidity without selling the asset.
- **Lenders** provide GRAM and decide which collections, rates, amounts, and durations they want to finance.

There are no shared liquidity pools in the protocol. Each lender manages their own funds independently, and each loan is handled separately through smart contracts.

## For Borrowers

- Receive GRAM without selling an NFT
- See loan terms before confirming the deal
- Pay interest pro-rata when repaying early
- Repay on time and get the NFT back
- Manage actions through a personal wallet

## For Lenders

- Issue loans in GRAM based on a custom strategy
- Choose collections and deal parameters independently
- Earn from borrower repayments
- Control liquidity directly without a shared pool

## How It Works

1. A lender sets loan terms and provides liquidity in GRAM.
2. A borrower selects available terms and sends an NFT as collateral.
3. Smart contracts lock the NFT and transfer GRAM to the borrower.
4. If the loan is repaid, the NFT returns to its owner, and early repayment charges interest pro-rata for the actual time used.
5. If the loan becomes overdue, the lender can claim the collateral.

## Why TonLender

- **Self-custody**: users act from their own wallets
- **On-chain execution**: loan logic is enforced by smart contracts
- **P2P model**: lenders control funds and risk directly
- **Clear outcome**: repayment returns the NFT, default transfers collateral to the lender
- **No artificial loan cap**: active loans scale with available lender liquidity

## Important Notes

- Loans are backed by NFTs, and market risk remains with participants.
- If a borrower misses the repayment deadline, the lender can claim the NFT.
- The protocol does not guarantee profit, NFT liquidity, or collateral resale price.

## Public Documentation

- English version: [docs.tonlender.com/en](https://docs.tonlender.com/en)
- Русская версия: [docs.tonlender.com/ru](https://docs.tonlender.com/ru)

## Mainnet Contract

- `LoanController`: `EQBOKsLNkny2Y9HKSnQ6OyVj42pvZ8-btU62hjZEwmTYWluy`

## How The Flow Is Structured

This README lists only the `LoanController` address because it is the main public contract of the protocol.

- **LoanController** coordinates loan issuance and repayment
- **LenderEscrow** is deployed separately for each lender and stores that lender's liquidity
- **Vault** is created separately for each specific collateral position and holds the NFT until repayment or default

From a user perspective, the flow looks like this: a lender sets up a personal `LenderEscrow`, a borrower uses available liquidity, a dedicated `Vault` is created for that deal, and `LoanController` connects these parts into one flow.

---

## Русский

TonLender — это P2P-протокол займов на блокчейне TON, в котором заёмщики могут получать **GRAM** под залог NFT, а кредиторы могут выдавать **GRAM** на своих условиях.

## Что Делает Продукт

TonLender соединяет две стороны рынка:

- **Заёмщики** используют NFT как залог и получают ликвидность без продажи актива.
- **Кредиторы** предоставляют GRAM и сами определяют коллекции, ставки, суммы и сроки, которые готовы финансировать.

В протоколе нет общих пулов ликвидности. Каждый кредитор управляет своими средствами самостоятельно, а каждый займ обрабатывается отдельно через смарт-контракты.

## Для Заёмщиков

- Получить GRAM без продажи NFT
- Увидеть условия займа до подтверждения сделки
- При досрочном погашении заплатить процент только pro-rata за фактическое время пользования средствами
- Вернуть займ в срок и получить NFT обратно
- Управлять действиями через собственный кошелёк

## Для Кредиторов

- Выдавать займы в GRAM по собственной стратегии
- Самостоятельно выбирать коллекции и параметры сделок
- Получать доход из выплат заёмщиков
- Напрямую управлять своей ликвидностью без общего пула

## Как Это Работает

1. Кредитор задаёт условия займа и предоставляет ликвидность в GRAM.
2. Заёмщик выбирает доступные условия и отправляет NFT в залог.
3. Смарт-контракты блокируют NFT и переводят GRAM заёмщику.
4. Если займ погашается, NFT возвращается владельцу, а при досрочном погашении процент рассчитывается pro-rata за фактическое время пользования средствами.
5. Если срок просрочен, кредитор может забрать залог.

## Почему Выбирают TonLender

- **Self-custody**: пользователи работают со своих кошельков
- **On-chain исполнение**: логика займа закреплена в смарт-контрактах
- **P2P-модель**: кредиторы сами контролируют средства и риск
- **Понятный исход сделки**: погашение возвращает NFT, просрочка переводит залог кредитору
- **Масштабируемость без искусственного лимита**: активных займов может быть столько, сколько позволяет ликвидность кредитора

## Что Важно Понимать

- Займы обеспечены NFT, а рыночный риск остаётся на стороне участников.
- Если заёмщик пропускает срок погашения, кредитор может забрать NFT.
- Протокол не гарантирует прибыль, ликвидность NFT или цену перепродажи залога.

## Публичная Документация

- Русская версия: [docs.tonlender.com/ru](https://docs.tonlender.com/ru)
- English version: [docs.tonlender.com/en](https://docs.tonlender.com/en)

## Mainnet Contract

- `LoanController`: `EQBOKsLNkny2Y9HKSnQ6OyVj42pvZ8-btU62hjZEwmTYWluy`

## Как Устроен Flow

В README указан только адрес `LoanController`, потому что это основной публичный контракт протокола.

- **LoanController** координирует выдачу и погашение займов
- **LenderEscrow** создаётся отдельно для каждого кредитора и хранит его ликвидность
- **Vault** создаётся отдельно под каждый конкретный залог и держит NFT до погашения или дефолта

С точки зрения пользователя flow выглядит так: кредитор заводит свой `LenderEscrow`, заёмщик приходит на доступную ликвидность, под сделку создаётся отдельный `Vault`, а `LoanController` связывает эти части в один сценарий.
