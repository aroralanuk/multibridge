// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.8.9;

import "./interfaces/IMultiMessageReceiver.sol";
import "./MessageStruct.sol";
import "./interfaces/EIP5164/ExecutorAware.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract MultiMessageReceiver is IMultiMessageReceiver, ExecutorAware, Initializable {
    // minimum accumulated power precentage for each message to be executed
    uint64 public quorumThreshold;

    // srcChainId => multiMessageSender
    mapping(uint256 => address) public multiMessageSenders;

    struct MsgInfo {
        bool executed;
        mapping(address => bool) from; // bridge receiver adapters that has already delivered this message.
    }
    // msgId => MsgInfo
    mapping(bytes32 => MsgInfo) public msgInfos;

    event ReceiverAdapterUpdated(address receiverAdapter, bool add);
    event MultiMessageSenderUpdated(uint256 chainId, address multiMessageSender);
    event QuorumThresholdUpdated(uint64 quorumThreshold);
    event SingleBridgeMsgReceived(uint256 srcChainId, string indexed bridgeName, uint32 nonce, address receiverAdapter);
    event MessageExecuted(uint256 srcChainId, uint32 nonce, address target, bytes callData);

    /**
     * @notice A modifier used for restricting the caller of some functions to be configured receiver adapters.
     */
    modifier onlyReceiverAdapter() {
        require(isTrustedExecutor(msg.sender), "not allowed bridge receiver adapter");
        _;
    }

    /**
     * @notice A modifier used for restricting the caller of some functions to be this contract itself.
     */
    modifier onlySelf() {
        require(msg.sender == address(this), "not self");
        _;
    }

    /**
     * @notice A modifier used for restricting that only messages sent from MultiMessageSender would be accepted.
     */
    modifier onlyFromMultiMessageSender() {
        require(_msgSender() == multiMessageSenders[_fromChainId()], "this message is not from MultiMessageSender");
        _;
    }

    /**
     * @notice A one-time function to initialize contract states.
     */
    function initialize(
        uint256[] calldata _srcChainIds,
        address[] calldata _multiMessageSenders,
        address[] calldata _receiverAdapters,
        uint64 _quorumThreshold
    ) external initializer {
        require(_multiMessageSenders.length > 0, "empty MultiMessageSender list");
        require(_multiMessageSenders.length == _srcChainIds.length, "mismatch length");
        require(_receiverAdapters.length > 0, "empty receiver adapter list");
        require(_quorumThreshold <= _receiverAdapters.length, "invalid threshold");
        for (uint256 i; i < _multiMessageSenders.length; ++i) {
            require(_multiMessageSenders[i] != address(0), "MultiMessageSender is zero address");
            _updateMultiMessageSender(_srcChainIds[i], _multiMessageSenders[i]);
        }
        for (uint256 i; i < _receiverAdapters.length; ++i) {
            require(_receiverAdapters[i] != address(0), "receiver adapter is zero address");
            _updateReceiverAdapter(_receiverAdapters[i], true);
        }
        quorumThreshold = _quorumThreshold;
    }

    /**
     * @notice Receive messages from allowed bridge receiver adapters.
     * If the accumulated power of a message has reached the power threshold,
     * this message will be executed immediately, which will invoke an external function call
     * according to the message content.
     */
    function receiveMessage(
        MessageStruct.Message calldata _message
    ) external override onlyReceiverAdapter onlyFromMultiMessageSender {
        uint256 srcChainId = _fromChainId();
        // This msgId is totally different with each adapters' internal msgId(which is their internal nonce essentially)
        // Although each adapters' internal msgId is attached at the end of calldata, it's not useful to MultiMessageReceiver.
        bytes32 msgId = getMsgId(_message, srcChainId);
        MsgInfo storage msgInfo = msgInfos[msgId];
        require(msgInfo.from[msg.sender] == false, "already received from this bridge adapter");

        msgInfo.from[msg.sender] = true;
        emit SingleBridgeMsgReceived(srcChainId, _message.bridgeName, _message.nonce, msg.sender);

        _executeMessage(_message, srcChainId, msgInfo);
    }

    /**
     * @notice Update bridge receiver adapters.
     * This function can only be called by _executeMessage() invoked within receiveMessage() of this contract,
     * which means the only party who can make these updates is the caller of the MultiMessageSender at the source chain.
     */
    function updateReceiverAdapter(
        address[] calldata _receiverAdapters,
        bool[] calldata _operations
    ) external onlySelf {
        require(_receiverAdapters.length == _operations.length, "mismatch length");
        for (uint256 i; i < _receiverAdapters.length; ++i) {
            _updateReceiverAdapter(_receiverAdapters[i], _operations[i]);
        }
    }

    /**
     * @notice Update MultiMessageSender on source chain.
     * This function can only be called by _executeMessage() invoked within receiveMessage() of this contract,
     * which means the only party who can make these updates is the caller of the MultiMessageSender at the source chain.
     */
    function updateMultiMessageSender(
        uint256[] calldata _srcChainIds,
        address[] calldata _multiMessageSenders
    ) external onlySelf {
        require(_srcChainIds.length == _multiMessageSenders.length, "mismatch length");
        for (uint256 i; i < _multiMessageSenders.length; ++i) {
            _updateMultiMessageSender(_srcChainIds[i], _multiMessageSenders[i]);
        }
    }

    /**
     * @notice Update power quorum threshold of message execution.
     * This function can only be called by _executeMessage() invoked within receiveMessage() of this contract,
     * which means the only party who can make these updates is the caller of the MultiMessageSender at the source chain.
     */
    function updateQuorumThreshold(uint64 _quorumThreshold) external onlySelf {
        require(_quorumThreshold <= trustedExecutor.length
            && _quorumThreshold > 0, "invalid threshold");
        quorumThreshold = _quorumThreshold;
        emit QuorumThresholdUpdated(_quorumThreshold);
    }

    /**
     * @notice Compute message Id.
     * message.bridgeName is not included in the message id.
     */
    function getMsgId(MessageStruct.Message calldata _message, uint256 _srcChainId) public pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(_srcChainId, _message.dstChainId, _message.nonce, _message.target, _message.callData)
            );
    }

    /**
     * @notice Execute the message (invoke external call according to the message content) if the message
     * has reached the power threshold (the same message has been delivered by enough multiple bridges).
     */
    function _executeMessage(
        MessageStruct.Message calldata _message,
        uint256 _srcChainId,
        MsgInfo storage _msgInfo
    ) private {
        if (_msgInfo.executed) {
            return;
        }
        uint64 msgPower = _computeMessagePower(_msgInfo);
        if (msgPower >= quorumThreshold) {
            _msgInfo.executed = true;
            (bool ok, ) = _message.target.call(_message.callData);
            require(ok, "external message execution failed");
            emit MessageExecuted(_srcChainId, _message.nonce, _message.target, _message.callData);
        }
    }

    function _computeMessagePower(MsgInfo storage _msgInfo) private view returns (uint64) {
        uint64 msgPower;
        for (uint256 i; i < trustedExecutor.length; ++i) {
            address adapter = trustedExecutor[i];
            if (_msgInfo.from[adapter]) {
                ++msgPower;
            }
        }
        return msgPower;
    }

    function _updateReceiverAdapter(address _receiverAdapter, bool _add) private {
        if (_add) {
            _addTrustedExecutor(_receiverAdapter);
        } else {
            _removeTrustedExecutor(_receiverAdapter);
            require(quorumThreshold <= trustedExecutor.length, "insufficient total power after removal");
        }
        emit ReceiverAdapterUpdated(_receiverAdapter, _add);
    }

    function _updateMultiMessageSender(uint256 _srcChainId, address _multiMessageSender) private {
        multiMessageSenders[_srcChainId] = _multiMessageSender;
        emit MultiMessageSenderUpdated(_srcChainId, _multiMessageSender);
    }
}
