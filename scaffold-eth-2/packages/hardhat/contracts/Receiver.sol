// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {IGhoToken} from './IGhoToken.sol';
import "./IERC20.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";

/**
 * THIS IS AN EXAMPLE CONTRACT THAT USES HARDCODED VALUES FOR CLARITY.
 * THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */

struct Bucket {
    uint256 collateral;
    uint256 amount;
    uint256 CollateralWorth;
    address user;
    bool drained;
}

/// @title - A simple contract for receiving string data across chains.
contract Receiver is CCIPReceiver, OwnerIsCreator {
    error NotEnoughBalance(uint256 currentBalance, uint256 calculatedFees); // Used to make sure contract has enough balance.

    event MessageSent(
        bytes32 indexed messageId, // The unique ID of the CCIP message.
        uint64 indexed destinationChainSelector, // The chain selector of the destination chain.
        address receiver, // The address of the receiver on the destination chain.
        uint256 id, // The id being sent.
        address feeToken, // the token address used to pay CCIP fees.
        uint256 fees // The fees paid for sending the CCIP message.
    );

    // Event emitted when a message is received from another chain.
    event MessageReceived(
        bytes32 indexed messageId, // The unique ID of the message.
        uint64 indexed sourceChainSelector, // The chain selector of the source chain.
        address sender, // The address of the sender from the source chain.
        string text // The text that was received.
    );

    bytes32 private s_lastReceivedMessageId; // Store the last received messageId.
    string private s_lastReceivedText; // Store the last received text.

    IGhoToken public ghoToken;
    IERC20 public ghoErc;
    IRouterClient private s_router;
    LinkTokenInterface private s_linkToken;
    AggregatorV3Interface internal dataFeed;
    uint64 public destinationChainSelector = 16015286601757825753; //sepolia hardcoded for testing
    address public senderVault;

    uint256 bucketIndex;
    uint256[] public activeBuckets;
    mapping(uint256 => Bucket) public allbuckets;
    mapping(address => uint256[]) public userBuckets;

    /// @notice Constructor initializes the contract with the router address.
    /// @param router The address of the router contract.
    constructor(address router, address _ghoToken, address _link, address _senderVault) CCIPReceiver(router) {
        ghoToken = IGhoToken(_ghoToken);
        ghoErc = IERC20(_ghoToken);
        dataFeed = AggregatorV3Interface(
            0x007A22900a3B98143368Bd5906f8E17e9867581b  // BTC/USD mumbai
        );
        s_router = IRouterClient(router);
        s_linkToken = LinkTokenInterface(_link);
        senderVault = _senderVault;
    }

    /// handle a received message
    function _ccipReceive(
        Client.Any2EVMMessage memory any2EvmMessage
    ) internal override {
        // s_lastReceivedMessageId = any2EvmMessage.messageId; // fetch the messageId
        // s_lastReceivedText = abi.decode(any2EvmMessage.data, (string)); // abi-decoding of the sent text
        // (string memory _name, uint256 _amount, address _user) = abi.decode(
        //     any2EvmMessage.data,
        //     (string, uint256, address)
        // );

        (string memory action, uint256 id, uint256 collateral, uint256 amount, uint256 collateralWorth, address user) = abi.decode(
            any2EvmMessage.data,
            (string, uint256, uint256, uint256, uint256, address)
        );

        activeBuckets.push(bucketIndex);
        userBuckets[user].push(bucketIndex);
        
        allbuckets[bucketIndex++] = 
            Bucket({
                collateral: collateral,
                amount: amount,
                CollateralWorth: collateralWorth,
                user: user,
                drained: false
            });

        ghoToken.mint(user, amount);

        emit MessageReceived(
            any2EvmMessage.messageId,
            any2EvmMessage.sourceChainSelector, // fetch the source chain identifier (aka selector)
            abi.decode(any2EvmMessage.sender, (address)), // abi-decoding of the sender address,
            abi.decode(any2EvmMessage.data, (string))
        );
    }

    function destroy(uint256 id) public {
        require(bucketIndex > id , "nonexistent bucket id");
        Bucket storage chosenBucket =  allbuckets[id];
        require(chosenBucket.drained == false, "cant drain same bucket twice");
        chosenBucket.drained = true;
        ghoErc.transferFrom(msg.sender, address(this), chosenBucket.amount);
        if (chosenBucket.user == msg.sender) {
            sendMessage(senderVault, id);
        } else {
        uint256 collateralWorth = (uint256(getChainlinkDataFeedLatestAnswer()) * chosenBucket.collateral) / uint256(getChainlinkDecimal()) / 18;
            require((chosenBucket.amount / 2 * 3) < collateralWorth,  "Cant liquidate");
            sendMessage(senderVault, id);
        }
    }

    function getChainlinkDecimal() public view returns (uint8) {
        return dataFeed.decimals();
    }

    function getChainlinkDataFeedLatestAnswer() public view returns (int) {
        // prettier-ignore
        (
            /* uint80 roundID */,
            int answer,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = dataFeed.latestRoundData();
        return answer;
    }

    function sendMessage(
        address receiver,
        uint256 id
    ) public onlyOwner returns (bytes32 messageId) {
        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver), // ABI-encoded receiver address
            data: abi.encode(id, msg.sender), // ABI-encoded string
            tokenAmounts: new Client.EVMTokenAmount[](0), // Empty array indicating no tokens are being sent
            extraArgs: Client._argsToBytes(
                // Additional arguments, setting gas limit
                Client.EVMExtraArgsV1({gasLimit: 600_000})
            ),
            // Set the feeToken  address, indicating LINK will be used for fees
            feeToken: address(s_linkToken)
        });

        // Get the fee required to send the message
        uint256 fees = s_router.getFee(
            destinationChainSelector,
            evm2AnyMessage
        );

        if (fees > s_linkToken.balanceOf(address(this)))
            revert NotEnoughBalance(s_linkToken.balanceOf(address(this)), fees);

        // approve the Router to transfer LINK tokens on contract's behalf. It will spend the fees in LINK
        s_linkToken.approve(address(s_router), fees);

        // Send the message through the router and store the returned message ID
        messageId = s_router.ccipSend(destinationChainSelector, evm2AnyMessage);

        // Emit an event with message details
        emit MessageSent(
            messageId,
            destinationChainSelector,
            receiver,
            id,
            address(s_linkToken),
            fees
        );

        // Return the message ID
        return messageId;
    }

    /// @notice Fetches the details of the last received message.
    /// @return messageId The ID of the last received message.
    /// @return text The last received text.
    function getLastReceivedMessageDetails()
        external
        view
        returns (bytes32 messageId, string memory text)
    {
        return (s_lastReceivedMessageId, s_lastReceivedText);
    }
}
