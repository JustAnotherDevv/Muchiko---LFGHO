// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "./IERC20.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";

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

/// @title - A simple contract for sending string data across chains.
contract CollateralLockerSender is OwnerIsCreator, CCIPReceiver {
    // Custom errors to provide more descriptive revert messages.
    error NotEnoughBalance(uint256 currentBalance, uint256 calculatedFees); // Used to make sure contract has enough balance.

    // Event emitted when a message is sent to another chain.
    event MessageSent(
        bytes32 indexed messageId, // The unique ID of the CCIP message.
        uint64 indexed destinationChainSelector, // The chain selector of the destination chain.
        address receiver, // The address of the receiver on the destination chain.
        string text, // The text being sent.
        address feeToken, // the token address used to pay CCIP fees.
        uint256 fees // The fees paid for sending the CCIP message.
    );

    IRouterClient private s_router;
    LinkTokenInterface private s_linkToken;
    AggregatorV3Interface internal dataFeed;
    IERC20 public collateralToken;
    address public receiverFacilitator;
    uint64 public destinationChainSelector = 12532609583862916517;
    uint256 public protocolRewards;

    Bucket[] public buckets;
    mapping(address => uint256[]) public userBuckets;
    mapping(address => uint256) public userBucketAmount;

    /// @notice Constructor initializes the contract with the router address.
    /// @param _router The address of the router contract.
    /// @param _link The address of the link contract.
    constructor(address _router, address _link, address _collateralToken, address _receiverFacilitator) CCIPReceiver(_router) {
        s_router = IRouterClient(_router);
        s_linkToken = LinkTokenInterface(_link);
        dataFeed = AggregatorV3Interface(
            0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43
        );
        collateralToken = IERC20(_collateralToken);
        receiverFacilitator = _receiverFacilitator;
    }

    function _ccipReceive(
        Client.Any2EVMMessage memory any2EvmMessage
    ) internal override {
        (uint256 id, address user) = abi.decode(
            any2EvmMessage.data,
            (uint256, address)
        );

        Bucket storage chosenBucket =  buckets[id];
        chosenBucket.drained = true;
        collateralToken.transfer(user, chosenBucket.collateral / 100 * 99);
        protocolRewards += chosenBucket.collateral / 100;
    }

    function deposit(uint256 _collateral, uint256 _amount) public {
        collateralToken.transferFrom(msg.sender, address(this), _collateral);
        uint256 collateralWorth = getCurrentCollateralWorth(_collateral);
        uint256 decimals = uint256(getChainlinkDecimal());
        // require((collateralWorth / 200) >= _amount , "low collateral");
        require((collateralWorth / 2) >= _amount / (10**10) , "low collateral");
        require(collateralWorth != 0 || _amount != 0 , "collateral worth is 0");

        sendMessage(receiverFacilitator, "DEPOSIT", _collateral, _amount, collateralWorth, buckets.length);
        userBuckets[msg.sender].push(buckets.length);
        userBucketAmount[msg.sender]++;
        buckets.push(
            Bucket({
                collateral: _collateral,
                amount: _amount,
                CollateralWorth: collateralWorth,
                user: msg.sender,
                drained: false
            })
                );
    }

    function getCurrentCollateralWorth(uint256 _collateral) public view returns (uint256) {
        uint256 tokenPrice = uint256(getChainlinkDataFeedLatestAnswer());
        uint256 decimals = uint256(getChainlinkDecimal());
        require(decimals > 0, "Invalid decimals");

        // return (_collateral * tokenPrice) / (10**decimals) / (10**18);

        return (_collateral * tokenPrice) / (10**18);// / (10**decimals) / (10**18);
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

    /// @notice Sends data to receiver on the destination chain.
    /// @dev Assumes your contract has sufficient LINK.
    /// @param receiver The address of the recipient on the destination blockchain.
    /// @param text The string text to be sent.
    /// @return messageId The ID of the message that was sent.
    function sendMessage(
        address receiver,
        string memory text,
        uint256 collateral,
        uint256 amount,
        uint256 collateralWorth,
        uint256 id
    ) public onlyOwner returns (bytes32 messageId) {
        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver), // ABI-encoded receiver address
            data: abi.encode(text, id, collateral, amount, collateralWorth, msg.sender), // ABI-encoded string
            tokenAmounts: new Client.EVMTokenAmount[](0), // Empty array indicating no tokens are being sent
            extraArgs: Client._argsToBytes(
                // Additional arguments, setting gas limit
                Client.EVMExtraArgsV1({gasLimit: 900_000})
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
            text,
            address(s_linkToken),
            fees
        );

        // Return the message ID
        return messageId;
    }

    function withdrawRewards() public onlyOwner {
        collateralToken.transfer(msg.sender, protocolRewards);
        protocolRewards = 0;
    }

    function setFacilitator(address _receiverFacilitator) public onlyOwner {
        receiverFacilitator = _receiverFacilitator;
    }
}
