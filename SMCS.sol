// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ISMCS.sol";
import "../Shared/Ownable.sol";

contract SMCS is Ownable, ISMCS
{
    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    mapping(address => bool) public mintAccessAccounts;

    uint256 private _totalSupply;
    uint256 private _totalBurn;

    string private constant NAME = "Smart Casino Token";
    string private constant SYMBOL = "SMCS";
    uint8 private constant DECIMALS = 18;

    constructor() 
    {
        mintAccessAccounts[address(this)] = true;

        _mint(_msgSender(), 100000 * (DECIMALS ** 10));
    }

    modifier onlyMintAccess() 
    {
        require(mintAccessAccounts[_msgSender()]);
        _;
    }

    function name() public view virtual override returns (string memory) 
    {
        return NAME;
    }

    function symbol() public view virtual override returns (string memory) 
    {
        return SYMBOL;
    }

    function decimals() public view virtual override returns (uint8) 
    {
        return DECIMALS;
    }

    function totalSupply() public view virtual override returns (uint256) 
    {
        return _totalSupply;
    }

    function totalBurn() public view returns (uint256)
    {
        return _totalBurn;
    }

    function balanceOf(address account) public view virtual override returns (uint256) 
    {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) 
    {
        address owner = _msgSender();
        _transfer(owner, to, amount);
        return true;
    }

    function allowance(address owner, address spender) public view virtual override returns (uint256) 
    {
        return _allowances[owner][spender];
    }

    function setMintAccess(address account, bool value) external onlyOwner returns (bool)
    {
        mintAccessAccounts[account] = value;
        return true;
    }

    function mint(address recipient, uint256 amount) external virtual override onlyMintAccess returns (bool)
    {
        _mint(recipient, amount);
        return true;
    }

    function burn(uint256 amount) external virtual override returns (bool)
    {
        _burn(_msgSender(), amount);
        return true;
    }

    function burnFrom(address account, uint256 amount) external virtual override returns (bool) 
    {
        _spendAllowance(account, _msgSender(), amount);
        _burn(account, amount);
        return true;
    }

    function approve(address spender, uint256 amount) public virtual override returns (bool) 
    {
        address owner = _msgSender();
        _approve(owner, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) 
    {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) 
    {
        address owner = _msgSender();
        _approve(owner, spender, allowance(owner, spender) + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) 
    {
        address owner = _msgSender();
        uint256 currentAllowance = allowance(owner, spender);
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");

        unchecked 
        {
            _approve(owner, spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal virtual 
    {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");

        unchecked 
        {
            _balances[from] = fromBalance - amount;
        }

        _balances[to] += amount;

        emit Transfer(from, to, amount);
    }

    function _burn(address account, uint256 amount) internal virtual 
    {
        require(account != address(0), "ERC20: burn from the zero address");

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");

        unchecked 
        {
            _balances[account] = accountBalance - amount;
        }

        _totalSupply -= amount;
        _totalBurn += amount;

        emit Transfer(account, address(0), amount);
    }

    function _mint(address account, uint256 amount) internal virtual 
    {
        require(account != address(0), "ERC20: mint to the zero address");

        _totalSupply += amount;
        _balances[account] += amount;

        emit Transfer(address(0), account, amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal virtual 
    {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _spendAllowance(address owner, address spender, uint256 amount) internal virtual 
    {
        uint256 currentAllowance = allowance(owner, spender);

        if (currentAllowance != type(uint256).max) 
        {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");

            unchecked 
            {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }
}