pragma solidity >=0.6.0;

import './F2M-Libraries.sol';

contract Film2Market {
    
    using SafeMath for uint;

    IUniswapV2Pair public defaultPair;

    address public admin;
    address private liquidityManager;
    address public CBK;
    
    address[] public pathUSD;

    uint public liquidityPercent;
    uint public slippage;
    
    struct Token {
        bool accepted;//The project has been explicitly accepted to participate in the YellowDapp. Other projects can also participate.
        uint price;//Price in CBK 
        uint redeemedCBK;//The amount of CBK that have been purchased with a certain token
        uint redeemedUSD;//The USD value of redeemedCBK for a certain token
        uint converted;//The amount of tokens that have been converted to CBK
        bool finalizedWithoutSuccess;//There's a timeline and ethics behind production. A token that doesn't redeem enough CBK in time or does not comply with our ethic code can have its offer finalized. 
        bool finalizedWithSuccess;//Enough CBK have been redeemed and the producer will begin filming about the project.
    }

    struct Pair {
        address routerAddress;//Address of the router
        address token;//Address of the token paired to CBK.
        bool registeredPair;//Returns true if the Pair has been registered.
    }
        
    struct Router {
        string dexName;//Name of the protocol
        uint fee;//The swap fee percentage that each protocol charges.
        uint param1;//Parameters used to do calculations to add liquidity
        uint param2;
        uint param3;
        uint param4;
        bool registeredRouter;//Returns true if the Router has been registered.
    }
    
    mapping(address => Token) public tokens;
    mapping(address => Pair) public pairs;
    mapping(address => Router) public routers;
    mapping(address => mapping (address => uint)) public deposited;

    event Converted(address indexed token, uint spent, uint bought);
    event Deposited(address indexed user, address indexed token, uint amount);
    event NewTokenAccepted(address indexed token, uint price);
    event FinalizedWithoutSuccess(address indexed token, uint balance, uint usd, uint spent, uint redeemed, uint price);
    event FinalizedWithSuccess(address indexed token, uint usd, uint spent, uint redeemed, uint price);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);


    constructor () public {
        defaultPair = IUniswapV2Pair(0x2F5C1A13b3d67211a30098E134c71F8Dea8C6303);
        admin = msg.sender;
        liquidityManager = msg.sender;
        CBK = 0x4f60a160D8C2DDdaAfe16FCC57566dB84D674BD6;
        liquidityPercent = 1000;
        registerRouter(0x10ED43C718714eb63d5aA57B78B54704E256024E, 25, "Pancakeswap", 399000000, 399000625, 19975, 19950);
        registerPair(0x2F5C1A13b3d67211a30098E134c71F8Dea8C6303, 0x10ED43C718714eb63d5aA57B78B54704E256024E);
        setSlippage(20);
        pathUSD = [0x4f60a160D8C2DDdaAfe16FCC57566dB84D674BD6, 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c, 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56];
    }
    
    //MODIFIER
    
    //This modifier requires a user to be the admin to interact with some functions.
    modifier onlyOwner() {
        require(msg.sender == admin, "Only the owner is allowed to access this function.");
        _;
    }
    

    //PUBLIC

    //The public can deposit tokens of accepted projects.
    //First users need to approve this smartcontract address in the token they wish to deposit.
    function depositToken(address token, uint amount) public {
        require(tokens[token].accepted == true, "Token not accepted");
        require(IERC20(token).transferFrom(msg.sender, address(this), amount), "transferFrom() failed");
        deposited[token][msg.sender] += amount;
        emit Deposited(msg.sender, token, amount);
    }
    
    
    //MANAGER - OnlyOwner
    
    //Admin can withdraw an amount any ERC20 token held in this smartcontract.
    function adminWithdrawToken(address token, uint amount) onlyOwner public {
        IERC20(token).transfer(admin, amount);
    }
    
    //Admin can withdraw ALL balance of any ERC20 token held in this smartcontract.
    function adminWithdrawTokenAll(address token) onlyOwner public {
        adminWithdrawToken(token, IERC20(token).balanceOf(address(this)));
    }
    
    //Admin can add a new token for community voting/pooling
    function acceptToken(address token, uint _price) onlyOwner public {
        tokens[token].accepted = true;
        tokens[token].price = _price;
        tokens[token].finalizedWithoutSuccess = false;
        emit NewTokenAccepted(token, _price);
    }

    //Admin can register a new pair.
    function registerPair(address newPair, address router) onlyOwner public {
        require(routers[router].registeredRouter == true, "Router not registered");
        pairs[newPair].routerAddress = router;//Address of the router
        pairs[newPair].token = IUniswapV2Pair(newPair).token0() == CBK ? IUniswapV2Pair(newPair).token1() : IUniswapV2Pair(newPair).token0();
        pairs[newPair].registeredPair = true;
    }
    
    //Admin can register a new router.
    function registerRouter(address router, uint fee, string memory dexName, uint _param1, uint _param2, uint _param3, uint _param4) onlyOwner public {
        routers[router].fee = fee;//The swap fee percentage that each protocol charges *100: For a 0.3% fee -> input 30. 
        routers[router].dexName = dexName;//Name of the protocol
        routers[router].param1 = _param1;//Parameters used to do calculations to swap and add liquidity. They vary depending on the swap fee
        routers[router].param2 = _param2;
        routers[router].param3 = _param3;
        routers[router].param4 = _param4;
        routers[router].registeredRouter = true;
    }

    //Admin can set a new default pair for liquidity management
    function setDefaultPair(address _pair) onlyOwner public {
        require(pairs[_pair].registeredPair == true, "Pair not registered");
        defaultPair = IUniswapV2Pair(_pair);
    }
    
    //Admin can transfer destination of the LP tokens to a different admin address.
    function changeLiquidityManager(address _newManager) onlyOwner public {
        liquidityManager = _newManager;
    }
    
    //Admin can set the percentages that are added to liquidity in the addLiquidity() function.
    //Set in ‰ (10 = 1%)
    function setLiquidityPercentage(uint _toLiquidity) onlyOwner public {
        require(_toLiquidity <= 1000, "Max liquidityPercent: 1000");
        liquidityPercent = _toLiquidity;
    }

    //Admin can end the offer of a token.
    function endOffer(address token) onlyOwner public {
        tokens[token].finalizedWithoutSuccess = true;
        tokens[token].accepted = false;
        emit FinalizedWithoutSuccess(token, IERC20(token).balanceOf(address(this)), tokens[token].converted, tokens[token].redeemedUSD, tokens[token].redeemedCBK, tokens[token].price);
    }
    
    function checkValueUSDforCBK(uint amountCBK) public view returns(uint) {
        (uint[] memory amountsOut) = IUniswapV2Router01(pairs[address(defaultPair)].routerAddress).getAmountsOut(amountCBK, pathUSD);
        uint i = amountsOut.length - 1;
        return amountsOut[i];
    }
    
    function setPathUSD(address[] memory _path) onlyOwner public {
        pathUSD = _path;
    }
    
    //The owner can convert an arbitrary amount of third-party tokens to CBK in a DEX
    //The CBK obtained and the tokens spent are counted
    function convertTokenToCBK(uint amount, uint amountOutMin, address[] memory path, address router) onlyOwner public returns(uint) {
        address token = path[0];
        uint balanceBeforeCBK = IERC20(CBK).balanceOf(address(this));
        uint balanceBeforeToken = IERC20(token).balanceOf(address(this));
        swapTokens(amount, amountOutMin, path, router);
        uint balanceAfterCBK = IERC20(CBK).balanceOf(address(this));
        uint balanceAfterToken = IERC20(token).balanceOf(address(this));
        uint bought = balanceAfterCBK-balanceBeforeCBK;
        uint spent = balanceBeforeToken-balanceAfterToken;
        tokens[token].redeemedCBK += bought;
        uint usd = checkValueUSDforCBK(bought);
        tokens[token].redeemedUSD += usd;
        tokens[token].converted += spent;
        checkIfFinalized(token);
        emit Converted(token,spent,bought);
        return bought;
    }
    
    //Function used to calculate the amount of CBK that need to be sold in order to add 100% of the selected amount value to liquidity.
    function calculateOtherHalf(uint reserveAmount, uint amount) onlyOwner public view returns(uint) {
        address defaultRoute = pairs[address(defaultPair)].routerAddress;
        uint half = SafeMath.sqrt(reserveAmount.mul(amount.mul(routers[defaultRoute].param1)
        .add(reserveAmount.mul(routers[defaultRoute].param2))))
        .sub(reserveAmount.mul(routers[defaultRoute].param3)) / routers[defaultRoute].param4;
        return half;
    }
    
    //The owner can convert an arbitrary amount of CBK in a DEX for an equal value of LP tokens
    function CBKtoLP(uint _amount) onlyOwner public {
        uint amount = _amount*liquidityPercent/1000;
        require(amount > 0);
        // 1. Compute the optimal amount of CBK to be converted to BNB. Based on 0.25% fee.
        (uint r0, uint r1, ) = defaultPair.getReserves();
        uint rIn = defaultPair.token0() == CBK ? r0 : r1;
        uint amountHalved = calculateOtherHalf(rIn, amount);
        uint balanceBefore = IERC20(CBK).balanceOf(address(this));
        // 2. Convert that portion of CBK tokens to the other token.
        address[] memory path = new address[](2);
        path[0] = CBK;
        path[1] = pairs[address(defaultPair)].token;
        IUniswapV2Router02(pairs[address(defaultPair)].routerAddress).swapExactTokensForTokens(
            amountHalved, 0, path, address(this), now);
        uint CBKtoLiquidity = balanceBefore.sub(IERC20(CBK).balanceOf(address(this)));
        // 3. Mint LP tokens
        addLiquidity(CBKtoLiquidity);
    }
    
    //The owner can convert an arbitrary amount of third-party tokens to CBK in a DEX and convert those CBK for an equal value of LP tokens
    function convertTokenToCBKLP(uint amount, uint amountOutMin, address[] memory path, address _router) onlyOwner public {
        uint toLP = convertTokenToCBK(amount, amountOutMin, path, _router);
        CBKtoLP(toLP);
    }

    //Approve any amount of token in this smartcontract to be spent by spender
    function approveToken(address token, address spender, uint amount) onlyOwner public {
        IERC20(token).approve(spender, amount);
    }
    
    //Transfers ownership of the contract to a new account (`newOwner`).
    //Can only be called by the current owner.
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }
    
    //Admin can set default slippage value.
    //Set in ‰ (_slippage = 10 = 1%).
    function setSlippage(uint _newSlippage) onlyOwner public {
        slippage = _newSlippage;
    }
    
    
    //INTERNAL

    //Transfers ownership of the contract to a new account (`newOwner`).
    //Internal function without access restriction.
    function _transferOwnership(address newOwner) internal {
        address oldOwner = admin;
        admin = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
    
    //This function is a protection against frontrunning attempts by bots when adding liquidity
    function safeMin(uint amountCBK) internal view returns(uint){
        uint _safeMin = (amountCBK*1000)/(1000+slippage);
        return _safeMin;
    }

    //Add liquidity to the DEX pool.
    function addLiquidity(uint amountCBK) internal {
        uint tokenBalance = IERC20(pairs[address(defaultPair)].token).balanceOf(address(this));
        uint minCBK = safeMin(amountCBK);
        uint minToken = safeMin(tokenBalance);
        (, , uint lpAmount) = IUniswapV2Router02(pairs[address(defaultPair)].routerAddress).addLiquidity(
        CBK, pairs[address(defaultPair)].token, amountCBK, tokenBalance, minCBK, minToken, liquidityManager, now);
        require(lpAmount >= 1, 'insufficient LP tokens received');
    }

    //This internal function buys CBK from DEX using tokens.
    function swapTokens(uint amountIn, uint amountOutMin, address[] memory path, address router) internal {
        IUniswapV2Router02(router).swapExactTokensForTokens(amountIn, amountOutMin, path, address(this), now);
    }

    //Check if a token has been converted to enough CBK
    function checkIfFinalized(address token) internal {
        if(tokens[token].accepted == true && tokens[token].redeemedUSD >= tokens[token].price) {
            tokens[token].finalizedWithSuccess = true;
            emit FinalizedWithSuccess(token, tokens[token].converted, tokens[token].redeemedUSD, tokens[token].redeemedCBK, tokens[token].price);
        }
    }
}
