
# Multi-Message Aggregation (MMA) Design

> **This is a temporary implementation of EIP5164, does not represent the final MultiBridge resolution**

> **For latest documentation, you can find it here:** https://multi-message-aggregation.gitbook.io/multi-message-aggregation/


Multi-Message Aggregation (MMA) is a solution for cross-chain message passing without vendor lock-in and enhanced security beyond any single bridge.
**A message with multiple copies is sent through different bridges to the destination chains, and will only be executed at the destination chain when the same message has been delivered by a quorum of different bridges.**

The current solution is designed for messages being sent from one source chain to multiple destination chains. It also requires that there is only one permitted sender on the source chain. For example, one use case could be a governance contract on Ethereum calling remote functions of contracts on other EVM chains. Each dApp that wants to utilize this framework needs to deploy its own set of contracts.

## Workflow

### High-level example


Assume, we use 3 bridges to relay governance message from Ethereum mainnet to a destination chain. (This number can be changed during actual deployment or via a later governance vote.)


On the destination chain, if 2 of the 3 bridges agree with each other, we would consider the message.

The flow of the message and how it is transformed and relayed is detailed below:

1. Uniswap Ethereum governance structure, `src`, approves to execute a message `msg` on destination chain `dst`.
2. Uniswap governance sends `msg` to `MultiMessageSender`. `MultiMessageSender` is owned by Uniswap governance.
3. `MultiMessageSender` relays `msg` to different adapters `adapter`.
4. `adapter` encodes `msg` into the corresponding formatted message, `formatted_msg`, and sends it to the hardcoded bridge contracts `bridge`.
5. Each `bridge` independently carries `formatted_msg` to `dst`.
6. On the destination chain, another set of `adapter`s decodes `formatted_msg`s into the original `msg`s.
7. `msg` is collected inside the `MultiMessageReceiver` contract.
8. If 2 out of 3 `msg` is the same, the `msg` will be executed on `dst`.

### Send message on source chain

To send a message to execute a remote call on the destination chain, sender on the source chain should call [`remoteCall()`](https://github.com/celer-network/multibridge/blob/cb35235b32b638d1f6fb8e5a8a78571516b40954/contracts/MultiMessageSender.sol#L43-L87) of `MultiMessageSender`, which invokes `dispatchMessage()` of every bridge sender adapter to send messages via different message bridges.

```
┌────────────────────────────────────────────────────────────────────────────────────────────┐
│ Source chain                                                                               │
│                                                                                            │
│                                                ┌─────────────────┐   ┌───────────────────┐ │
│                                             ┌─►│ Bridge1 Adapter ├──►│ Bridge1 Contracts │ │
│                                             │  └─────────────────┘   └───────────────────┘ │
│        remoteCall           dispatchMessage │                                              │
│ ┌────────┐    ┌────────────────────┐        │  ┌─────────────────┐   ┌───────────────────┐ │
│ │ Caller ├───►│ MultiMessageSender ├────────┼─►│ Bridge2 Adapter ├──►│ Bridge2 Contracts │ │
│ └────────┘    └────────────────────┘        │  └─────────────────┘   └───────────────────┘ │
│                                             │                                              │
│                                             │  ┌─────────────────┐   ┌───────────────────┐ │
│                                             └─►│ Bridge3 Adapter ├──►│ Bridge3 Contracts │ │
│                                                └─────────────────┘   └───────────────────┘ │
│                                                                                            │
└────────────────────────────────────────────────────────────────────────────────────────────┘
```

### Receive message on destination chain

On the destination chain, MultiMessageReceiver receives messages from every bridge receiver adapter. Each receiver adapter gets encoded message data from its bridge contracts, and then decodes the message and call `receiveMessage()` of `MultiMessageReceiver`.

`MultiMessageReceiver` maintains a map from bridge adapter address to its power. Only adapter with non-zero power has access to `receiveMessage()` function. If the accumulated power of a message has reached a threshold, which means enough different bridges have delivered the same message, the message will be placed in a timelock before executed by the `MultiBrideReceiver` contract. An additional guardian multisig can be added to veto a timelocked message.

**Note: Both timelock and optional guardian multisig are in development.**

The message execution will invoke a function call according to the message content, which will either call functions of other receiver contracts, or call the param adjustment functions (e.g., add/remove adapter, update threshold) of the `MultiMessageReceiver` itself. **Note that the only legit message sender is the trusted caller on the source chain, which means only that single source chain caller can trigger function calls of the `MultiMessageReceiver` contracts on desitnation chains.**

```
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│ Destination chain                                                                           │
│                                                                                             │
│ ┌───────────────────┐   ┌─────────────────┐                                                 │
│ │ Bridge1 Contracts ├──►│ Bridge1 Adapter ├─┐                                               │
│ └───────────────────┘   └─────────────────┘ │                                               │
│                                             │receiveMessage              call               │
│ ┌───────────────────┐   ┌─────────────────┐ │     ┌──────────────────────┐     ┌──────────┐ │
│ │ Bridge1 Contracts ├──►│ Bridge2 Adapter ├─┼────►│ MultiMessageReceiver ├────►│ Receiver │ │
│ └───────────────────┘   └─────────────────┘ │     └──────────────────────┘     └──────────┘ │
│                                             │                                               │
│ ┌───────────────────┐   ┌─────────────────┐ │                                               │
│ │ Bridge2 Contracts ├──►│ Bridge3 Adapter ├─┘                                               │
│ └───────────────────┘   └─────────────────┘                                                 │
│                                                                                             │
└─────────────────────────────────────────────────────────────────────────────────────────────┘
```

### Add new bridge and update threshold

Below are steps to add a new bridge (e.g., Bridge4) by governance community.

1. Bridge4 provider should implement and deploy Bridge4 adapters on the source chain and all destination chains. The adapter contracts should meet the following requirements.

   - On the source chain, the sender adapter should only accept `dispatchMessage()` call from `MultiMessageSender`.
   - On the destination chain, the receiver adapter should only accept messages sent from the Bridge4 sender adapter on the source chain, and then call `receiveMessage()` of `MultiMessageReceiver` for each valid message.

   - Renounce any ownership or special roles of the adapter contracts after initial setup.
2. Bridge4 provider deploys the adapter contracts and makes them open source. The dApp community should review the code and check if the requirements above are met.
3. dApp contract (`Caller`) on the source chain adds the new Bridge4 receiver adapter to `MultiMessageReceiver` on the destination chain by calling the [`remoteCall()`](https://github.com/celer-network/multibridge/blob/cb35235b32b638d1f6fb8e5a8a78571516b40954/contracts/MultiMessageSender.sol#L43-L87) function of `MultiMessageSender`, with arguments to call [`updateReceiverAdapter()`](https://github.com/celer-network/multibridge/blob/cb35235b32b638d1f6fb8e5a8a78571516b40954/contracts/MultiMessageReceiver.sol#L84-L89) of the `MultiMessageReceiver` on the destination chain.
4. dApp contract (`Caller`) on the source chain adds the new Bridge4 sender adapter to `MultiMessageSender` on the source chain by calling the `addSenderAdapters()` function of `MultiMessageSender`.

Updating the quorum threshold is similar to configuring a new bridge receiver adapter on destination chains. It requires a `remoteCall()` from the source chain `Caller` with calldata calling [`updateQuorumThreshold()`](https://github.com/celer-network/multibridge/blob/cb35235b32b638d1f6fb8e5a8a78571516b40954/contracts/MultiMessageReceiver.sol#L96-L100) of the `MultiMessageReceiver` on the destination chain.

## Example

>NOTE: The following deployment and test example is using contract codes without EIP5164 implementation.

Use case: `Caller`(address: 0x58b529F9084D7eAA598EB3477Fe36064C5B7bbC1) on Avalanche Fuji send message to [`UniswapV3Factory` on BSC Testnet](https://testnet.bscscan.com/address/0x0bec2a9e08658eaa15935c25cff953cab2934c85) through `Celer` and `Wormhole`, in order to call `enableFeeAmount()` for state change.

### Deployment and initialization

- Deploy `MultiMessageSender` on Avalanche Fuji with `Caller`'s address, [tx link](https://testnet.snowtrace.io/tx/0x59552174e6b703b5b955f105011e9b5ffff4540008a83d1a03a7b957e25678f0).
- Deploy `MultiMessageReceiver` on BSC Testnet, [tx link](https://testnet.bscscan.com/tx/0x5583bbf67d2c3a61a829707e6a69dad1802bcb04b91c203a2669fe23b75c04c2).
- Deploy `CelerSenderAdapter` on Avalanche Fuji, [tx link](https://testnet.snowtrace.io/tx/0xb8ecfb91c88ac4fca1270c214ec54d03ec459a33cab76358c6fbe17a6dbb9588). Set `MultiMessageSender`, [tx link](https://testnet.snowtrace.io/tx/0x7dcebb3169ef443cdf5893a0653b76a13999ebfea0bc9120e8b2aa5a565c1d03).
- Deploy `CelerReceiverAdapter` on BSC Testnet, [tx link](https://testnet.bscscan.com/tx/0x1a21abd8d0acd6208f6c179f6cae3222e4642bfe27d37cdbdaf60df34b230ef8). Set `MultiMessageReceiver`, [tx link](https://testnet.bscscan.com/tx/0xe9791cc984fbf5925b079d74198cefd7b0477e45eec6f3a90665fc1512096fbd).
- Register `CelerReceiverAdapter` in `CelerSenderAdapter`, [tx link](https://testnet.snowtrace.io/tx/0xf41951f31a274af5748cce0250b4b7e193f99adc43a1af53aa368ec10acf7d01).
- Register `CelerSenderAdapter` in `CelerReceiverAdapter`, [tx link](https://testnet.bscscan.com/tx/0x4887c0d53594654291a546964433df88b1190185e79dd0b487310ee0562569ef).
- Renounce owner of `CelerSenderAdapter` and `CelerReceiverAdapter`. **Not actually did in this example for easier debugging**.
- Deployer of `MultiMessageReceiver` initialize this contact, register `CelerReceiverAdapter` with power `10000`, and set `quorumThreshold` to `100`, [tx link](https://testnet.bscscan.com/tx/0x578dc2edf7969819eec0a941c127ae619de1cf5040fad666a022d383b13eec5e).
- `Caller` register `CelerSenderAdapter` in `MultiMessageSender`, [tx link](https://testnet.snowtrace.io/tx/0x21e2a97077259a7a1d9bb9cbc2c8f9101a1576e04f40d6fb08b51b87cec55e6e).

### Test cross-chain updating quorum threshold through single bridge(Celer)

`Caller` make a call to `remoteCall()` of `MultiMessageSender` with calldata calling `updateQuorumThreshold()` of `MultiMessageReceiver`, in order to update quorum threshold to `98`, [tx link](https://testnet.snowtrace.io/tx/0x2cc5746f2b95fe4cea4bfbc901867f6f2245f90cb05447ce0294122e7878a8cd).

`MultiMessageReceiver` receive message from `CelerReceiverAdapter` and update quorum threshold to `98`, [tx link](https://testnet.bscscan.com/tx/0xee2ba1f80abd8018d46c4cd26758c4b979c7760e6babc53efb171114864a345c).

### Add a new bridge Wormhole

- Deploy `WormholeSenderAdapter` on Avalanche Fuji, [tx link](https://testnet.snowtrace.io/tx/0x15d2c38a34a16900eb1fea45772d77db098edf6007de87fa556ebadabcfa1b09). Set `MultiMessageSender`, [tx link](https://testnet.snowtrace.io/tx/0x03f344717822f17570f79fad8c464de50910a2c31bcd4ad6b696c300de26dcbf). Set a chain id map from formal chain id to the one used by Wormhole, [tx link](https://testnet.snowtrace.io/tx/0x03f344717822f17570f79fad8c464de50910a2c31bcd4ad6b696c300de26dcbf).
- Deploy `WormholeReceiverAdapter` on BSC Testnet, [tx link](https://testnet.bscscan.com/tx/0xa2f7ddf9090c2cff94e9464aa69dc8d5a2bca07eb6c43202d94bbdccc5505e32). Set `MultiMessageReceiver`, [tx link](https://testnet.bscscan.com/tx/0xc3775851890604b5b1428eccd9b1a7776e5e5825899771e1159fd17beaa58870).
- Register `WormholeReceiverAdapter` in `WormholeSenderAdapter`, [tx link](https://testnet.snowtrace.io/tx/0xe8e64d5410b078f202e1f15b4862ce15ee69603c172f9e073f2b84502fe7f507).
- Register `WormholeSenderAdapter` in `WormholeReceiverAdapter`, [tx link](https://testnet.bscscan.com/tx/0x3d8268fbe9774673b94653391adf75c995aaac562c18cc04ffd4aea5e1e6d1aa).
- Renounce owner of `WormholeSenderAdapter` and `WormholeReceiverAdapter`. **Not actually did in this example for easier debugging**.
- `Caller` make a call to `remoteCall()` of `MultiMessageSender` with calldata calling `updateReceiverAdapter()` of `MultiMessageReceiver`, in order to register `WormholeReceiverAdapter` in `MultiMessageReceiver` with power `10000`, [tx link](https://testnet.snowtrace.io/tx/0x132487b65c81bf48fecb5d5896ff806977f963a63ed9d86db9b71b9f8e11beea).
- `MultiMessageReceiver` receive message from `CelerReceiverAdapter` and register`WormholeReceiverAdapter` with power `10000`, [tx link](https://testnet.bscscan.com/tx/0x74ff55798eb5388711cfb310bf523b8f369b233879ae4db004bea1165be21c59).
- `Caller` register `WormholeSenderAdapter` in `MultiMessageSender`, [tx link](https://testnet.snowtrace.io/tx/0xaa0b63c1c3a890eb661c21b6dcfb0b9816f604d2ecd912f00073ff99f7738a48).

### Test cross-chain updating quorum threshold through two bridges(Celer&Wormhole)

`Caller` make a call to `remoteCall()` of `MultiMessageSender` with calldata calling `updateQuorumThreshold()` of `MultiMessageReceiver`, in order to update quorum threshold to `96`, [tx link](https://testnet.snowtrace.io/tx/0x57066c9809d0e0d139cd611982b9c04121fd2ead1a812c43bb91ecb4aa25b8a2).

`MultiMessageReceiver` receive message from `WormholeReceiverAdapter`, [tx link](https://testnet.bscscan.com/tx/0xe72cecfe6656120f9d7eaf8565f2d26acfd650e9bc0f5d1754104e435c84f1fa). Accumulated power of this message is `10000/20000` and not reaches quorum threshold `98/100`.

`MultiMessageReceiver` receive message from `CelerReceiverAdapter`, [tx link](https://testnet.bscscan.com/tx/0x0ceaf9315cfd2a9c42c597a3aba4566ac5b15f54dce42bc25e96d0bdd12475ff). Accumulated power of this message changes to `20000/20000` and reaches quorum threshold `98/100`. Then within the same tx, quorum threshold is updated to `96`.

### Test cross-chain calling enableFeeAmount() of UniswapV3Factory

`UniswapV3Factory` for testing is deployed on BSC Testnet, [tx link](https://testnet.bscscan.com/tx/0x279030c5e404058c3d669e55797e0400d174f7ef373267d18378b157d76d46ed).

Transfer owner of `UniswapV3Factory` to `MultiMessageReceiver`, because `enableFeeAmount()` is only callable from owner. [tx link](https://testnet.bscscan.com/tx/0x1255f37a8a7a3aa7fa13e2321038d557db14fc99a8e65324f58acdb16de3cac4).

`Caller` make a call to `remoteCall()` of `MultiMessageSender` with calldata calling `enableFeeAmount()` of `UniswapV3Factory`, in order to update `feeAmountTickSpacing[40] = 40`, [tx link](https://testnet.snowtrace.io/tx/0xa6f2b3af99773f6d03b5b31b37e95732366fbe6d25a5c2dc6358ab88860047a0).

`MultiMessageReceiver` receive message from `WormholeReceiverAdapter`, [tx link](https://testnet.bscscan.com/tx/0x2db8178ce5130945fee24fc7da3d5273921234dd6fa10655f5baaea6f90cb2f5). Accumulated power of this message is `10000/20000` and not reaches quorum threshold `96/100`.

`MultiMessageReceiver` receive message from `CelerReceiverAdapter`, [tx link](https://testnet.bscscan.com/tx/0xfbb0680033a841cadf197cf6b85f5794f764f2edeb27192353edd3cf668987fe). Accumulated power of this message changes to `20000/20000` and reaches quorum threshold `96/100`. Then within the same tx, `MultiMessageReceiver` invoke `enableFeeAmount()` of `UniswapV3Factory` and set `feeAmountTickSpacing[40] = 40`.
