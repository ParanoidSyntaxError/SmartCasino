// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IHousePool.sol";
import "../Shared/Ownable.sol";
import "../Shared/IERC20.sol";
import "./ISMCS.sol";

// DONE: Coin flip
// DONE: Withdraw
// DONE: Reward HousePool interactions with SMCS

// TODO: Testing
// TODO: Big wheel
// TODO: Comments

contract SmartCasino is Ownable
{
    struct CoinFlipData
    {
        uint256 lastTimestamp;

        // [token][timestamp][player] = amount
        mapping(address => mapping(uint256 => mapping(address => uint256))) bets;
        // [token][timestamp][index] = player
        mapping(address => mapping(uint256 => address[])) players;
    }

    struct BigWheelData
    {
        uint256 lastTimestamp;

        // [token][timestamp][player] = amount
        mapping(address => mapping(uint256 => mapping(address => uint256[6]))) bets;
        // [token][timestamp][index] = player
        mapping(address => mapping(uint256 => address[])) players;
    }

    // [token][timestamp] = requestId
    mapping(address => mapping(uint256 => uint256)) private _requestIds;
    // [token][requestId] = timestamp
    mapping(address => mapping(uint256 => uint256)) private _timestamps;
    // [token][requestId] = is balance updated
    mapping(address => mapping(uint256 => bool)) private _balanceUpdated;

    IHousePool public immutable housePool;

    ISMCS public immutable smcs;

    CoinFlipData private _coinFlip;

    BigWheelData private _bigWheel;

    // [token][player] = balance
    mapping(address => mapping(address => uint256)) public _tokenBalances;

    bytes32 private _keyHash;
    uint32 private _callbackGasLimit;
    uint16 private _requestConfirmations;
    uint64 private _subscriptionId;

    constructor()
    {
        housePool = IHousePool(0x156506363BbeeB3B9BA9E938040ecFAD37310507);

        smcs = ISMCS(0xb4128706d9Bf5088208C07b12Ef7d86d1c636Bd4);

        setVrfSettings(0xd4bb89654db74673a187bd804519e65e3f71a52bc55f11da7601a13dcf505314, 690, 3, 100000);
    }

    receive() external payable {}

    function setVrfSettings(bytes32 keyHash, uint64 subId, uint16 confirmations, uint32 gasLimit) public returns(bool)
    {
        _keyHash = keyHash;
        _subscriptionId = subId;
        _requestConfirmations = confirmations;
        _callbackGasLimit = gasLimit;

        return true;
    }

    function getVrfSettings() external view returns(bytes32, uint64, uint16, uint32)
    {
        return (_keyHash, _subscriptionId, _requestConfirmations, _callbackGasLimit);
    }

    function depositETH() public payable returns(bool)
    {
        _tokenBalances[housePool.getETHIndex()][msg.sender] += msg.value;

        return true;
    }

    function depositTokens(address token, uint256 amount) public returns(bool)
    {
        IERC20(token).transferFrom(msg.sender, address(this), amount);

        _tokenBalances[token][msg.sender] += amount;

        return true;
    }

    function withdrawTokens(address token, uint256 amount) public returns (bool)
    {
        require(amount > 0);
        require(_tokenBalances[token][msg.sender] >= amount);

        _tokenBalances[token][msg.sender] -= amount;

        if(token == address(1))
        {
            smcs.mint(msg.sender, amount);
        }
        else if(token == housePool.getETHIndex())
        {
            (bool success,) = msg.sender.call{value: amount}("");
            require(success);
        }
        else
        {
            IERC20(token).transfer(msg.sender, amount);
        }

        return true;
    }

    function betBigWheel(address token, uint256[6] memory amounts) public
    {
        uint256 totalWager = 0;

        bool isNewBet = true;

        for(uint256 i = 0; i < amounts.length; i++)
        {
            if(_bigWheel.bets[token][_bigWheel.lastTimestamp][msg.sender][i] > 0)
            {
                isNewBet = false;
            }

            _bigWheel.bets[token][_bigWheel.lastTimestamp][msg.sender][i] += amounts[i];

            totalWager += amounts[i];
        }

        if(isNewBet)
        {
            _bigWheel.players[token][_bigWheel.lastTimestamp].push(msg.sender);
        }

        // Does account have enough to bet
        require(totalWager <= _tokenBalances[token][msg.sender]);

        // Remove amount from account balance
        _tokenBalances[token][msg.sender] -= totalWager;
    }

    function rollBigWheel(address token) public
    {
        // Prevent overwriting timestamp to requestID mapping
        require(_bigWheel.lastTimestamp != block.timestamp);

        uint256[6] memory totalWagers;

        for(uint256 i = 0; i < _bigWheel.players[token][_bigWheel.lastTimestamp].length; i++)
        {
            for(uint256 a = 0; a < 6; a++)
            {
                totalWagers[a] += _bigWheel.bets[token][_bigWheel.lastTimestamp][_bigWheel.players[token][_bigWheel.lastTimestamp][i]][a];
            }
        }

        // Build bets array for house pool
        uint256[5][][] memory bets = new uint256[5][][](1);
        bets[0] = new uint256[5][](6);

        bets[0][0] = [totalWagers[0], 100, 1, 24, 51];
        bets[1][1] = [totalWagers[1], 300, 25, 36, 51];
        bets[2][2] = [totalWagers[2], 500, 37, 44, 51];
        bets[3][3] = [totalWagers[3], 1100, 45, 48, 51];
        bets[4][4] = [totalWagers[4], 2300, 49, 50, 51];
        bets[5][5] = [totalWagers[5], 4700, 51, 51, 51];

        uint256 totalWager = 0;

        for(uint256 i = 0; i < totalWagers.length; i++)
        {
            totalWager += totalWagers[i];
        }

        // Temp request ID
        uint256 requestId = 0;

        if(token == housePool.getETHIndex())
        {
            // ETH house pool roll request
            requestId = housePool.requestETHRoll{value : totalWager}(bets, _keyHash, _subscriptionId, _requestConfirmations, _callbackGasLimit);
        }
        else
        {
            // Approve tokens for transfer by house pool
            IERC20(token).approve((address)(housePool), totalWager);

            // ERC20 token house pool roll request
            requestId = housePool.requestTokenRoll(token, bets, _keyHash, _subscriptionId, _requestConfirmations, _callbackGasLimit);
        }

        // Assign request ID to timestamp
        _requestIds[token][_bigWheel.lastTimestamp] = requestId;
        _timestamps[token][requestId] = _coinFlip.lastTimestamp;

        // Get coin flip ready for the next round
        _bigWheel.lastTimestamp = block.timestamp;
    }

    function betCoinFlip(address token, uint256 amount) public
    {
        // Does account have enough to bet
        require(amount <= _tokenBalances[token][msg.sender]);

        // Remove amount from account balance
        _tokenBalances[token][msg.sender] -= amount;

        if(_coinFlip.bets[token][_coinFlip.lastTimestamp][msg.sender] == 0)
        {
            _coinFlip.players[token][_coinFlip.lastTimestamp].push(msg.sender);
        }
        
        _coinFlip.bets[token][_coinFlip.lastTimestamp][msg.sender] += amount;
    }

    function rollCoinFlip(address token) public
    {
        // Prevent overwriting timestamp to requestID mapping
        require(_coinFlip.lastTimestamp != block.timestamp);

        uint256 totalWager = 0;

        for(uint256 i = 0; i < _coinFlip.players[token][_coinFlip.lastTimestamp].length; i++)
        {
            totalWager += _coinFlip.bets[token][_coinFlip.lastTimestamp][_coinFlip.players[token][_coinFlip.lastTimestamp][i]];
        }

        // Build bets array for house pool
        uint256[5][][] memory bets = new uint256[5][][](1);
        bets[0] = new uint256[5][](1);

        bets[0][0] = [totalWager, 100, 1, 246, 500];

        // Temp request ID
        uint256 requestId = 0;

        if(token == housePool.getETHIndex())
        {
            // ETH house pool roll request
            requestId = housePool.requestETHRoll{value : totalWager}(bets, _keyHash, _subscriptionId, _requestConfirmations, _callbackGasLimit);
        }
        else
        {
            // Approve tokens for transfer by house pool
            IERC20(token).approve((address)(housePool), totalWager);

            // ERC20 token house pool roll request
            requestId = housePool.requestTokenRoll(token, bets, _keyHash, _subscriptionId, _requestConfirmations, _callbackGasLimit);
        }

        // Assign request ID to timestamp
        _requestIds[token][_coinFlip.lastTimestamp] = requestId;
        _timestamps[token][requestId] = _coinFlip.lastTimestamp;

        // Get coin flip ready for the next round
        _coinFlip.lastTimestamp = block.timestamp;
    }

    function collectFromHouse(uint256 requestId) public
    {
        (,address token,, uint256[5][][] memory bets) = housePool.getRoll(requestId);

        require(_balanceUpdated[token][requestId] == false);

        _balanceUpdated[token][requestId] = true;

        uint256 collected = housePool.withdrawRoll(requestId);

        if(collected == 0)
        {
            return;
        }

        uint256 timestamp = _timestamps[token][requestId];

        if(_coinFlip.players[token][timestamp].length > 0)
        {
            if(housePool.isWinningBet(requestId, 0, 0))
            {
                for(uint256 i = 0; i < _coinFlip.players[token][timestamp].length; i++)
                {
                    address player = _coinFlip.players[token][timestamp][i];

                    // Credit winnings
                    _tokenBalances[token][player] += _coinFlip.bets[token][timestamp][player] * 2;
                }
            }
        }
        else if(_bigWheel.players[token][timestamp].length > 0)
        {
            // Bet index
            for(uint256 i = 0; i < 6; i++)
            {
                if(housePool.isWinningBet(requestId, 0, i))
                {
                    // Player index
                    for(uint256 a = 0; a < _bigWheel.players[token][timestamp].length; a++)
                    {
                        address player = _bigWheel.players[token][timestamp][a];

                        // Credit winnings
                        _tokenBalances[token][player] += (_bigWheel.bets[token][timestamp][player][i] * bets[0][i][1]) / 100;
                    }
                
                    break;
                }
            }
        }

        if(token == address(1))
        {
            smcs.burn(collected);
        }

        smcs.mint(msg.sender, 200 * (smcs.decimals() ** 10));
    }
}
