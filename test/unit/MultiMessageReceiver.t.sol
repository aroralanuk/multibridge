// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "contracts/MultiMessageReceiver.sol";
import "contracts/MultiMessageSender.sol";
import "contracts/interfaces/IBridgeReceiverAdapter.sol";

contract MockReceiverAdapter is IBridgeReceiverAdapter {
    uint256 public constant MOCK_MESSAGE_FEE = 1000000000000000; // 10^15

    uint256 msgId;

    function updateSenderAdapter(
        uint256[] calldata,
        address[] calldata
    ) external override {
        // Do nothing
    }
}

contract TestMultiMessageReceiver is Test {
    MultiMessageReceiver mmr;
    address[] mms;
    address[] adapters;
    uint32[] adapterPowers;

    uint256[] exampleSrcChainId;

    function setUp() public {
        exampleSrcChainId.push(1);

        mms.push(address(new MultiMessageSender(address(this))));
        mmr = new MultiMessageReceiver();

        MockReceiverAdapter adapter1 = new MockReceiverAdapter();
        MockReceiverAdapter adapter2 = new MockReceiverAdapter();
        adapters.push(address(adapter1));
        adapters.push(address(adapter2));

        adapterPowers.push(1);
        adapterPowers.push(1);

    }

    function testInitialize() public {
        mmr.initialize(exampleSrcChainId, mms, adapters, adapterPowers, 2);

        assertEq(mmr.multiMessageSenders(1), address(mms[0]));
        assertEq(mmr.receiverAdapterPowers(address(adapters[0])), 1);
        assertEq(mmr.receiverAdapterPowers(address(adapters[1])), 1);
        assertEq(mmr.totalPower(), 2);
    }

    function testUpdateReceiverAdapter() public {
        address[] memory updatedAdapters = new address[](2);
        updatedAdapters[0] = address(0x1);
        updatedAdapters[1] = address(0x2);

        uint32[] memory updatedPowers = new uint32[](2);
        updatedPowers[0] = 1;
        updatedPowers[1] = 2;

        // mmr.updateReceiverAdapter(updatedAdapters, updatedPowers);
        // assertEq(mmr.receiverAdapterPowers(address(0x1)), 1);
        // assertEq(mmr.receiverAdapterPowers(address(0x2)), 2);
        // assertEq(mmr.totalPower(), 3);
    }

    // function testUpdateMultiMessageSender() public {
    //     mmr.updateMultiMessageSender(1, address(0x1));
    //     assertEq(mmr.multiMessageSenders(1), address(0x1));
    // }

    // function testUpdateQuorumThreshold() public {
    //     mmr.updateQuorumThreshold(1);
    //     assertEq(mmr.quorumThreshold(), 1);
    // }

    // function testReceiveSingleBridgeMsg() public {
    //     mmr.updateReceiverAdapter([1, 2], [address(0x1), address(0x2)]);
    //     mmr.updateMultiMessageSender(1, address(0x1));
    //     mmr.updateQuorumThreshold(1);
    //     mmr.receiveSingleBridgeMsg(1, "MockBridge", 1, address(0x1));
    //     assertEq(mmr.msgInfos(0).from[address(0x1)], true);
    //     assertEq(mmr.msgInfos(0).from[address(0x2)], false);
    //     assertEq(mmr.msgInfos(0).executed, false);
    // }

    // function testReceiveMultiBridgeMsg() public {
    //     mmr.updateReceiverAdapter([1, 2], [address(0x1), address(0x2)]);
    //     mmr.updateMultiMessageSender(1, address(0x1));
    //     mmr.updateQuorumThreshold(1);
    //     mmr.receiveMultiBridgeMsg(1, "MockBridge", 1, [address(0x1), address(0x2)], [1, 2]);
    //     assertEq(mmr.msgInfos(0).from[address(0x1)], true);
    //     assertEq(mmr.msgInfos(0).from[address(0x2)], true);
    //     assertEq(mmr.msgInfos(0).executed, true);
}
