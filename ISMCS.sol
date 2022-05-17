// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../Shared/IERC20.sol";
import "../Shared/IERC20Metadata.sol";

interface ISMCS is IERC20, IERC20Metadata 
{
    function mint(address to, uint256 amount) external returns (bool);

    function burn(uint256 amount) external returns (bool);

    function burnFrom(address account, uint256 amount) external returns (bool);
} 