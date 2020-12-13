pragma solidity ^0.6.0;

contract PrivateSale {
    
    using SafeMath for uint256;
    
    address payable public owner;
    uint256 public ratio = 9000000000000;
    IERC20 public token;
    IERC20 public usdc;
    IUniswapV2Pair public uni;
    uint256 public tokensSold;
    bool public saleEnded;
    uint256 public minimum = 45000 ether;
    uint256 public limit = 180000 ether;
    
    mapping(address => uint256) public permitted;
    
    event TokensPurchased(address indexed buyer, uint256 tokens, uint256 usdc, uint256 eth);
    event SaleEnded(uint256 indexed unsoldTokens, uint256 indexed collectedUSDC, uint256 indexed collectedETH);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner is allowed to access this function.");
        _;
    }
    
    constructor (address tokenAddress, address usdcAddress, address uniAddress) public {
        
        token = IERC20(tokenAddress);
        usdc = IERC20(usdcAddress);
        uni = IUniswapV2Pair(uniAddress);
        owner = msg.sender;
    }


    function permit(address account) onlyOwner public {
        permitted[account] += limit;
    }
    
    function setLimits(uint256 min, uint256 max) onlyOwner public {
        minimum = min;
        limit = max;
    }
    
    receive() external payable {
        buyWithETH();
    }
    
    function buyWithUSDC(uint256 amountUSDC) public {

        uint256 tokens = amountUSDC.mul(ratio);
        require(!saleEnded, "Sale has already ended");
        require(tokens <= token.balanceOf(address(this)), "Not enough tokens for sale");
        require(tokens <= permitted[msg.sender], "The amount exceeds your limit");
        require(tokens >= minimum, "The amount is less than minimum");
        permitted[msg.sender] -= tokens;
        require(usdc.transferFrom(msg.sender, address(this), amountUSDC));        
        require(token.transfer(msg.sender, tokens));
        tokensSold += tokens;

        emit TokensPurchased(msg.sender, tokens, amountUSDC, 0);
    }

    function buyWithETH() payable public {

        (uint112 a, uint112 b, uint32 c) = uni.getReserves();
        uint256 tokens = msg.value.mul(ratio).mul(a).div(b);
        require(!saleEnded, "Sale has already ended");
        require(tokens <= token.balanceOf(address(this)), "Not enough tokens for sale");
        require(tokens <= permitted[msg.sender], "The amount exceeds your limit");
        require(tokens >= minimum, "The amount is less than minimum");
        permitted[msg.sender] -= tokens;
        token.transfer(msg.sender, tokens);
        tokensSold += tokens;

        emit TokensPurchased(msg.sender, tokens, 0, msg.value);
    }
    
    function endSale() onlyOwner public {
        uint256 tokens = token.balanceOf(address(this));
        uint256 usd = usdc.balanceOf(address(this));
        uint256 eth = address(this).balance;
        token.transfer(owner, tokens);
        usdc.transfer(owner, usd);
        owner.transfer(eth);
        saleEnded = true;
        emit SaleEnded(tokens, usd, eth);
    }
    
    
}
