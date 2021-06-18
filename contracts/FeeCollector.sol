// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./utils/BalanceAccounting.sol";


contract FeeCollector is Ownable, BalanceAccounting {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;
    uint256 private immutable _k00;
    uint256 private immutable _k01;
    uint256 private immutable _k02;
    uint256 private immutable _k03;
    uint256 private immutable _k04;
    uint256 private immutable _k05;
    uint256 private immutable _k06;
    uint256 private immutable _k07;
    uint256 private immutable _k08;
    uint256 private immutable _k09;
    uint256 private immutable _k10;
    uint256 private immutable _k11;
    uint256 private immutable _k12;
    uint256 private immutable _k13;
    uint256 private immutable _k14;
    uint256 private immutable _k15;
    uint256 private immutable _k16;
    uint256 private immutable _k17;
    uint256 private immutable _k18;
    uint256 private immutable _k19;
    uint256 private constant _MAX_TIME = 0xfffff;

    struct EpochBalance {
        mapping(address => uint256) balances;
        uint256 totalSupply;
        uint256 tokenSpent;
        uint256 inchBalance;
    }

    struct TokenInfo {
        mapping(uint256 => EpochBalance) epochBalance;
        uint256 firstUnprocessedEpoch;
        uint256 currentEpoch;
        mapping(address => uint256) firstUserUnprocessedEpoch;
        uint256 lastPriceValue;
        uint256 lastTime;
    }

    mapping(IERC20 => TokenInfo) public tokenInfo;

    uint256 public immutable minValue;
    uint256 public lastTokenPriceValueDefault;
    uint256 public lastTokenTimeDefault;

    uint8 public immutable decimals;

    constructor(
        IERC20 _token,
        uint256 _minValue,
        uint256 _deceleration
    ) {
        require(_deceleration > 0 && _deceleration < 1e36, "Invalid deceleration");
        token = _token;
        decimals = IERC20Metadata(address(_token)).decimals();

        uint256 z;
        _k00 = z = _deceleration;
        _k01 = z = z * z / 1e36;
        _k02 = z = z * z / 1e36;
        _k03 = z = z * z / 1e36;
        _k04 = z = z * z / 1e36;
        _k05 = z = z * z / 1e36;
        _k06 = z = z * z / 1e36;
        _k07 = z = z * z / 1e36;
        _k08 = z = z * z / 1e36;
        _k09 = z = z * z / 1e36;
        _k10 = z = z * z / 1e36;
        _k11 = z = z * z / 1e36;
        _k12 = z = z * z / 1e36;
        _k13 = z = z * z / 1e36;
        _k14 = z = z * z / 1e36;
        _k15 = z = z * z / 1e36;
        _k16 = z = z * z / 1e36;
        _k17 = z = z * z / 1e36;
        _k18 = z = z * z / 1e36;
        _k19 = z = z * z / 1e36;
        require(z * z < 1e36, "Deceleration is too slow");

        minValue = lastTokenPriceValueDefault = _minValue;
        lastTokenTimeDefault = block.timestamp;
    }

    function decelerationTable() public view returns(uint256[20] memory) {
        return [
            _k00, _k01, _k02, _k03, _k04,
            _k05, _k06, _k07, _k08, _k09,
            _k10, _k11, _k12, _k13, _k14,
            _k15, _k16, _k17, _k18, _k19
        ];
    }

    function price(IERC20 _token) public view returns(uint256 result) {
        return priceForTime(block.timestamp, _token);
    }

    function priceForTime(uint256 time, IERC20 _token) public view returns(uint256 result) {
        uint256[20] memory table = [
            _k00, _k01, _k02, _k03, _k04,
            _k05, _k06, _k07, _k08, _k09,
            _k10, _k11, _k12, _k13, _k14,
            _k15, _k16, _k17, _k18, _k19
        ];
        uint256 lastTime = tokenInfo[_token].lastTime;
        uint256 secs = Math.min(time - lastTime, _MAX_TIME);
        result = Math.max(tokenInfo[_token].lastPriceValue, minValue);
        for (uint i = 0; secs > 0 && i < table.length; i++) {
            if (secs & 1 != 0) {
                result = result * table[i] / 1e36;
            }
            if (result < minValue) return minValue;
            secs >>= 1;
        }
    }

    function name() external view returns(string memory) {
        return string(abi.encodePacked("FeeCollector: ", IERC20Metadata(address(token)).name()));
    }

    function symbol() external view returns(string memory) {
        return string(abi.encodePacked("fee-", IERC20Metadata(address(token)).symbol()));
    }

    function updateRewards(address[] calldata receivers, uint256[] calldata amounts) external {
        for (uint i = 0; i < receivers.length; i++) {
            _updateReward(IERC20(msg.sender), receivers[i], amounts[i]);
        }
    }

    function updateReward(address referral, uint256 amount) external {
        _updateReward(IERC20(msg.sender), referral, amount);
    }

    function updateRewardNonLP(IERC20 erc20, address referral, uint256 amount) external {
        erc20.safeTransferFrom(msg.sender, address(this), amount);
        _updateReward(erc20, referral, amount);
    }

    function _updateReward(IERC20 erc20, address referral, uint256 amount) private {
        TokenInfo storage _token = tokenInfo[erc20];
        uint256 currentEpoch = _token.currentEpoch;

        _updateTokenState(erc20, int256(amount));

        // Add new reward to current epoch
        _token.epochBalance[currentEpoch].balances[referral] += amount;
        _token.epochBalance[currentEpoch].totalSupply += amount;

        // Collect all processed epochs and advance user token epoch
        _collectProcessedEpochs(referral, _token, currentEpoch);
    }

    function _updateTokenState(IERC20 erc20, int256 amount) private {
        TokenInfo storage _token = tokenInfo[erc20];
        uint256 currentEpoch = _token.currentEpoch;
        uint256 firstUnprocessedEpoch = _token.firstUnprocessedEpoch;

        uint256 fee = _token.epochBalance[firstUnprocessedEpoch].totalSupply - _token.epochBalance[firstUnprocessedEpoch].tokenSpent;
        if (firstUnprocessedEpoch != currentEpoch) {
            fee += (_token.epochBalance[currentEpoch].totalSupply - _token.epochBalance[currentEpoch].tokenSpent);
        }

        uint256 feeWithAmount = (amount >= 0 ? fee + uint256(amount) : fee - uint256(-amount));
        tokenInfo[erc20].lastPriceValue = priceForTime(block.timestamp, erc20) * feeWithAmount / (fee == 0 ? 1 : fee);
        tokenInfo[erc20].lastTime = block.timestamp;
    }

    function trade(IERC20 erc20, uint256 amount) external {
        TokenInfo storage _token = tokenInfo[erc20];
        uint256 firstUnprocessedEpoch = _token.firstUnprocessedEpoch;
        EpochBalance storage epochBalance = _token.epochBalance[firstUnprocessedEpoch];
        EpochBalance storage currentEpochBalance = _token.epochBalance[_token.currentEpoch];

        uint256 tokenBalance = _token.epochBalance[firstUnprocessedEpoch].totalSupply - _token.epochBalance[firstUnprocessedEpoch].tokenSpent;
        if (firstUnprocessedEpoch != _token.currentEpoch) {
            tokenBalance += (_token.epochBalance[_token.currentEpoch].totalSupply - _token.epochBalance[_token.currentEpoch].tokenSpent);
        }
        uint256 _price = price(erc20);
        uint256 returnAmount = amount * tokenBalance / _price;
        require(tokenBalance >= returnAmount, "not enough tokens");

        if (_token.firstUnprocessedEpoch == _token.currentEpoch) {
            _token.currentEpoch += 1;
        }

        _updateTokenState(erc20, -int256(returnAmount));

        if (returnAmount <= epochBalance.totalSupply - epochBalance.tokenSpent) {
            if (returnAmount == epochBalance.totalSupply - epochBalance.tokenSpent) {
                _token.firstUnprocessedEpoch += 1;
            }

            epochBalance.tokenSpent += returnAmount;
            epochBalance.inchBalance += amount;
        } else {
            uint256 amountPart = (epochBalance.totalSupply - epochBalance.tokenSpent) * amount / returnAmount;

            currentEpochBalance.tokenSpent += (returnAmount - (epochBalance.totalSupply - epochBalance.tokenSpent));
            currentEpochBalance.inchBalance += (amount - amountPart);

            epochBalance.tokenSpent = epochBalance.totalSupply;
            epochBalance.inchBalance += amountPart;

            _token.firstUnprocessedEpoch += 1;
            _token.currentEpoch += 1;
        }

        token.safeTransferFrom(msg.sender, address(this), amount);
        erc20.safeTransfer(msg.sender, returnAmount);
    }

    function claim(IERC20[] memory pools) external {
        for (uint256 i = 0; i < pools.length; ++i) {
            TokenInfo storage _token = tokenInfo[pools[i]];
            _collectProcessedEpochs(msg.sender, _token, _token.currentEpoch);
        }

        uint256 userBalance = balanceOf(msg.sender);
        if (userBalance > 1) {
            // Avoid erasing storage to decrease gas footprint for referral payments
            unchecked {
                uint256 withdrawn = userBalance - 1;
                _burn(msg.sender, withdrawn);
                token.safeTransfer(msg.sender, withdrawn);
            }
        }
    }

    function claimCurrentEpoch(IERC20 erc20) external {
        TokenInfo storage _token = tokenInfo[erc20];
        uint256 currentEpoch = _token.currentEpoch;
        uint256 userBalance = _token.epochBalance[currentEpoch].balances[msg.sender];
        if (userBalance > 0) {
            _token.epochBalance[currentEpoch].balances[msg.sender] = 0;
            _token.epochBalance[currentEpoch].totalSupply -= userBalance;
            erc20.safeTransfer(msg.sender, userBalance);
        }
    }

    function claimFrozenEpoch(IERC20 erc20) external {
        TokenInfo storage _token = tokenInfo[erc20];
        uint256 firstUnprocessedEpoch = _token.firstUnprocessedEpoch;
        uint256 currentEpoch = _token.currentEpoch;

        require(firstUnprocessedEpoch + 1 == currentEpoch, "Epoch already finalized");
        require(_token.firstUserUnprocessedEpoch[msg.sender] == firstUnprocessedEpoch, "Epoch funds already claimed");

        _token.firstUserUnprocessedEpoch[msg.sender] = currentEpoch;
        EpochBalance storage epochBalance = _token.epochBalance[firstUnprocessedEpoch];
        uint256 share = epochBalance.balances[msg.sender];

        if (share > 0) {
            uint256 totalSupply = epochBalance.totalSupply;
            epochBalance.balances[msg.sender] = 0;
            epochBalance.totalSupply = totalSupply - share;
            epochBalance.tokenSpent -= _transferTokenShare(erc20, epochBalance.tokenSpent, share, totalSupply);
            epochBalance.inchBalance -= _transferTokenShare(token, epochBalance.inchBalance, share, totalSupply);
        }
    }

    function _transferTokenShare(IERC20 _token, uint256 balance, uint256 share, uint256 totalSupply) private returns(uint256 amount) {
        amount = balance * share / totalSupply;
        if (amount > 0) {
            _token.safeTransfer(payable(msg.sender), amount);
        }
    }

    function _collectProcessedEpochs(address user, TokenInfo storage _token, uint256 currentEpoch) private {
        uint256 userEpoch = _token.firstUserUnprocessedEpoch[user];

        // Early return for the new users
        if (_token.epochBalance[userEpoch].balances[user] == 0) {
            _token.firstUserUnprocessedEpoch[user] = currentEpoch;
            return;
        }

        uint256 tokenEpoch = _token.firstUnprocessedEpoch;
        if (tokenEpoch <= userEpoch) {
            return;
        }
        uint256 epochCount = Math.min(2, tokenEpoch - userEpoch); // 0, 1 or 2 epochs

        // Claim 1 or 2 processed epochs for the user
        uint256 collected = _collectEpoch(user, _token, userEpoch);
        if (epochCount > 1) {
            collected += _collectEpoch(user, _token, userEpoch + 1);
        }
        _mint(user, collected);

        // Update user token epoch counter
        bool emptySecondEpoch = _token.epochBalance[userEpoch + 1].balances[user] == 0;
        _token.firstUserUnprocessedEpoch[user] = (epochCount == 2 || emptySecondEpoch) ? currentEpoch : userEpoch + 1;
    }

    function _collectEpoch(address user, TokenInfo storage _token, uint256 epoch) private returns(uint256 collected) {
        uint256 share = _token.epochBalance[epoch].balances[user];
        if (share > 0) {
            uint256 inchBalance = _token.epochBalance[epoch].inchBalance;
            uint256 totalSupply = _token.epochBalance[epoch].totalSupply;

            collected = inchBalance * share / totalSupply;

            _token.epochBalance[epoch].balances[user] = 0;
            _token.epochBalance[epoch].totalSupply = totalSupply - share;
            _token.epochBalance[epoch].inchBalance = inchBalance - collected;
        }
    }

    function getUserEpochBalance(address user, IERC20 _token, uint256 epoch) external view returns(uint256) {
        return tokenInfo[_token].epochBalance[epoch].balances[user];
    }

    function getTotalSupplyEpochBalance(IERC20 _token, uint256 epoch) external view returns(uint256) {
        return tokenInfo[_token].epochBalance[epoch].totalSupply;
    }

    function getTokenSpentEpochBalance(IERC20 _token, uint256 epoch) external view returns(uint256) {
        return tokenInfo[_token].epochBalance[epoch].tokenSpent;
    }

    function getInchBalanceEpochBalance(IERC20 _token, uint256 epoch) external view returns(uint256) {
        return tokenInfo[_token].epochBalance[epoch].inchBalance;
    }

    function getFirstUserUnprocessedEpoch(address user, IERC20 _token) external view returns(uint256) {
        return tokenInfo[_token].firstUserUnprocessedEpoch[user];
    }
}
