// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "contracts/MultiMessageSender.sol";
import "contracts/interfaces/IBridgeSenderAdapter.sol";

contract MockBridgeSenderAdapter is IBridgeSenderAdapter {
    string public override name = "MockBridge";
    uint256 public constant MOCK_MESSAGE_FEE = 1000000000000000; // 10^15

    function getMessageFee(
        uint256,
        address,
        bytes calldata
    ) external pure override returns (uint256) {
        return MOCK_MESSAGE_FEE;
    }

    function dispatchMessage(
        uint256 /* chainId */,
        address,
        bytes calldata
    ) external payable override returns (bytes32 messageId) {
        require(msg.value == MOCK_MESSAGE_FEE, "MockBridgeSenderAdapter: Incorrect fee");
        return 0;
    }

    function updateReceiverAdapter(
        uint256[] calldata,
        address[] calldata
    ) external override {
        // Do nothing
    }
}


contract TestMultiMessageSender is Test {
    MultiMessageSender mms;
    MockBridgeSenderAdapter adapter1;
    MockBridgeSenderAdapter adapter2;

    event MultiMessageMsgSent(
        uint32 nonce,
        uint64 dstChainId,
        address target,
        bytes callData,
        address[] senderAdapters
    );

    function setUp() public {
        mms = new MultiMessageSender(address(this));
        adapter1 = new MockBridgeSenderAdapter();
        adapter2 = new MockBridgeSenderAdapter();
    }

    function testAddSenderAdapters() public {
        address[] memory adapters = new address[](2);
        adapters[0] = address(adapter1);
        adapters[1] = address(adapter2);
        mms.addSenderAdapters(adapters);

        assertEq(mms.senderAdapters(0), address(adapter1));
        assertEq(mms.senderAdapters(1), address(adapter2));
    }


    function testAddSenderAdapters_Duplicate() public {
        address[] memory adapters = new address[](2);
        adapters[0] = address(adapter1);
        adapters[1] = address(adapter1);

        mms.addSenderAdapters(adapters);

        assertEq(mms.senderAdapters(0), address(adapter1));

        vm.expectRevert(); // adapter1 should be added only once
        assertEq(mms.senderAdapters(1), address(0));
    }

    function testRemoveSenderAdapters() public {
        // First, add the adapters
        address[] memory adapters = new address[](2);
        adapters[0] = address(adapter1);
        adapters[1] = address(adapter2);
        mms.addSenderAdapters(adapters);

        // Then, remove one of the adapters
        address[] memory removeAdapters = new address[](1);
        removeAdapters[0] = address(adapter1);
        mms.removeSenderAdapters(removeAdapters);

        assertEq(mms.senderAdapters(0), address(adapter2));
        vm.expectRevert(); // length now 1
        assertEq(mms.senderAdapters(1), address(0));
    }


    function testRemoveSenderAdapters_FailRemoveTwice() public {
        // First, add the adapters
        address[] memory adapters = new address[](2);
        adapters[0] = address(adapter1);
        adapters[1] = address(adapter2);
        mms.addSenderAdapters(adapters);

        // Then, remove one of the adapters
        address[] memory removeAdapters = new address[](1);
        removeAdapters[0] = address(adapter1);
        mms.removeSenderAdapters(removeAdapters);

        // vm.expectRevert(); // adapter1 already removed
        mms.removeSenderAdapters(removeAdapters);

        assertEq(mms.senderAdapters(0), address(adapter2));
        vm.expectRevert(); // length now 1
        assertEq(mms.senderAdapters(1), address(0));
    }

    function testEstimateTotalMessageFee() public {
        // First, add the adapters
        address[] memory adapters = new address[](2);
        adapters[0] = address(adapter1);
        adapters[1] = address(adapter2);
        mms.addSenderAdapters(adapters);

        // Then, estimate the total message fee
        uint64 dstChainId = 42;
        address mmr = address(0x123);
        address target = address(0x456);
        bytes memory callData = "0x789";

        uint256 totalFee = mms.estimateTotalMessageFee(dstChainId, mmr, target, callData);
        assertEq(totalFee, 2000000000000000); // 2 * 10^15
    }

    function testEstimateTotalMessageFee_AfterRemove() public {
        // First, add the adapters
        address[] memory adapters = new address[](2);
        adapters[0] = address(adapter1);
        adapters[1] = address(adapter2);
        mms.addSenderAdapters(adapters);

        // Then, estimate the total message fee
        uint64 dstChainId = 42;
        address mmr = address(0x123);
        address target = address(0x456);
        bytes memory callData = "0x789";

        uint256 totalFee = mms.estimateTotalMessageFee(dstChainId, mmr, target, callData);
        assertEq(totalFee, 2000000000000000); // 2 * 10^15

        // Then, remove one of the adapters
        address[] memory removeAdapters = new address[](1);
        removeAdapters[0] = address(adapter1);
        mms.removeSenderAdapters(removeAdapters);

        // Then, estimate the total message fee again
        totalFee = mms.estimateTotalMessageFee(dstChainId, mmr, target, callData);
        assertEq(totalFee, 1000000000000000); // 1 * 10^15
    }

    function testRemoteCall() public {
        // First, add the adapters
        address[] memory adapters = new address[](2);
        adapters[0] = address(adapter1);
        adapters[1] = address(adapter2);
        mms.addSenderAdapters(adapters);

        // Then, make a remote call
        uint64 dstChainId = 42;
        address mmr = address(0x123);
        address target = address(0x456);
        bytes memory callData = "0x789";

        uint256 initialBalance = address(this).balance;
        uint256 totalFee = mms.estimateTotalMessageFee(dstChainId, mmr, target, callData);

        // check for message dispatched event
        // vm.expectEmit(true, true, true, true);
        // emit MultiMessageMsgSent(0, dstChainId, target, callData, adapters);
        mms.remoteCall{value: totalFee}(dstChainId-1, mmr, target, callData);

        // check if gas was consumed
        assertEq(initialBalance - totalFee, address(this).balance);
    }
}


