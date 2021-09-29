//SPDX-License-Identifier: MIT
pragma solidity >=0.6.0;

import './F2M-Libraries.sol';

contract Film2Market {
    
    using SafeMath for uint;

    IUniswapV2Pair public defaultPair;//Default pair used to manage liquidity

    address public admin;//Owner of the smartcontract
    address private liquidityManager;//Address of the LP token receiver
    address public CBK;//Address of CBK
    
    address[] public pathUSD;//Path to calculate USD value of CBK

    uint public liquidityPercent;//Percentage to add to liquidity in addLiquidity()
    uint public slippage;//Slippage percentage
    
    struct Token {
        bool accepted;//The project has been explicitly accepted to participate in the YellowDapp. Other projects can also participate.
        uint price;//Price in CBK 
        uint redeemedCBK;//The amount of CBK that have been purchased with a certain token
        uint redeemedUSD;//The USD value of redeemedCBK for a certain token at conversion time
        uint converted;//The amount of tokens that have been converted to CBK
        bool finalizedWithoutSuccess;//A token that doesn't redeem enough CBK in time or does not comply with our ethic code can have its offer finalized. 
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
        //Parameters used to do calculations to convert CBK to CBK-LP
        uint param1;//param2-(fee^2)
        uint param2;//param3^2
        uint param3;//20000-fee
        uint param4;//20000-(fee*2)
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
    
    /**
     * @dev This modifier requires a user to be the admin to interact with some functions.
     */
    modifier onlyOwner() {
        require(msg.sender == admin, "Only the owner is allowed to access this function.");
        _;
    }
    

    //PUBLIC

    /**
     * @dev The public can deposit tokens of accepted projects.
     * First users need to approve this smartcontract address in the token they wish to deposit.
     * @param token Token to deposit
     * @param amount Amount of token to deposit
     */
    function depositToken(address token, uint amount) public {
        require(tokens[token].accepted == true, "Token not accepted");
        require(IERC20(token).transferFrom(msg.sender, address(this), amount), "transferFrom() failed");
        deposited[token][msg.sender] += amount;
        emit Deposited(msg.sender, token, amount);
    }
    
    
    //MANAGER - OnlyOwner
    
    /**
     * @dev Admin can withdraw any amount of ERC20 token held in this smartcontract.
     * @param token Token to withdraw
     */
    function adminWithdrawToken(address token, uint amount) onlyOwner public {
        IERC20(token).transfer(admin, amount);
    }
    
    /**
     * @dev Admin can withdraw ALL balance of any ERC20 token held in this smartcontract.
     * @param token Token to withdraw
     */
    function adminWithdrawTokenAll(address token) onlyOwner public {
        adminWithdrawToken(token, IERC20(token).balanceOf(address(this)));
    }
    
    /**
     * @dev Admin can add a new token for community voting/pooling
     * @param token Token/Project to accept
     * @param _price Price in USD (wei). Pay attention if the USD used in pathUSD is not 18 decimals.
     */
    function acceptToken(address token, uint _price) onlyOwner public {
        tokens[token].accepted = true;
        tokens[token].price = _price;
        tokens[token].finalizedWithoutSuccess = false;
        emit NewTokenAccepted(token, _price);
    }

    /**
     * @dev Admin can register a new pair.
     * Router must be registered before.
     * @param newPair Pair address (LP)
     * @param router Router address (LP) used to swap in newPair
     */
    function registerPair(address newPair, address router) onlyOwner public {
        require(routers[router].registeredRouter == true, "Router not registered");
        pairs[newPair].routerAddress = router;//Address of the router
        pairs[newPair].token = IUniswapV2Pair(newPair).token0() == CBK ? IUniswapV2Pair(newPair).token1() : IUniswapV2Pair(newPair).token0();
        pairs[newPair].registeredPair = true;
    }
    
    /**
     * @dev Admin can register a new router.
     * @param router Address of the royter
     * @param fee Divide 'fee' by 100 to get % (25 = 0.25%)
     * @param dexName Informative string with the name of the protocol
     */
    function registerRouter(address router, uint fee, string memory dexName, uint _param1, uint _param2, uint _param3, uint _param4) onlyOwner public {
        routers[router].fee = fee;//The swap fee percentage that each protocol charges *100: For a 0.3% fee -> input 30. 
        routers[router].dexName = dexName;//Name of the protocol
        routers[router].param1 = _param1;//Parameters used to do calculations to swap and add liquidity. They vary depending on the swap fee
        routers[router].param2 = _param2;
        routers[router].param3 = _param3;
        routers[router].param4 = _param4;
        routers[router].registeredRouter = true;
    }

    /**
     * @dev Admin can set a new default pair for liquidity management.
     * Pair must be registered before.
     * @param _pair Pair address (LP)
     */
    function setDefaultPair(address _pair) onlyOwner public {
        require(pairs[_pair].registeredPair == true, "Pair not registered");
        defaultPair = IUniswapV2Pair(_pair);
    }
    
    /**
     * @dev Change address of LP tokens receiver for addLiquidity()
     * @param _liquidityManager New receiver address
     */
    function changeLiquidityManager(address _liquidityManager) onlyOwner public {
        liquidityManager = _liquidityManager;
    }
    
    /**
     * @dev Admin can set the percentages that are added to liquidity in the addLiquidity() function.
     * @param _liquidityPercent Set in ‰ (10 = 1%)
     */
    function setLiquidityPercentage(uint _liquidityPercent) onlyOwner public {
        require(_liquidityPercent <= 1000, "Max liquidityPercent: 1000");
        liquidityPercent = _liquidityPercent;
    }

    /**
     * @dev The admin can cancel the offer to a project.
     * @param token Address of the token.
     */
    function endOffer(address token) onlyOwner public {
        tokens[token].finalizedWithoutSuccess = true;
        tokens[token].accepted = false;
        emit FinalizedWithoutSuccess(token, IERC20(token).balanceOf(address(this)), tokens[token].converted, tokens[token].redeemedUSD, tokens[token].redeemedCBK, tokens[token].price);
    }
    
    /**
     * @dev Uses pathUSD in defaultPair's router
     * @return USD value of amountCBK
     * @param amountCBK Amount of CBK
     */
    function checkValueUSDforCBK(uint amountCBK) public view returns(uint) {
        (uint[] memory amountsOut) = IUniswapV2Router01(pairs[address(defaultPair)].routerAddress).getAmountsOut(amountCBK, pathUSD);
        uint i = amountsOut.length - 1;
        return amountsOut[i];
    }

    /**
     * @dev The owner can set a new path to calculate USD value of CBK
     * @param _path Array of addresses where: first = CBK, last = USD
     */
    function setPathUSD(address[] memory _path) onlyOwner public {
        pathUSD = _path;
    }
    
    /**
     * @dev The owner can convert an arbitrary amount of third-party tokens to CBK in a DEX
     * The CBK obtained and the tokens spent are counted
     * @return Amount of CBK bought
     * @param amount Desired amount of token to be sold
     * @param amountOutMin Minimum amount of CBK to be bought
     * @param path Array of addresses where 1st position is the token to sell and last the token to buy.
     * Minimum 2 tokens, but can incude intermediary routes.
     * @param router Address of the DEX router used
     */
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
    
    /**
     * @dev Function used to calculate the amount of CBK that need to be sold in order to add 100% of the selected amount value to liquidity.
     * @return Amount to be sold
     * @param reserveAmount Amount of reserve token in the LP pair
     * @param amount Amount of CBK to be converted to LP
     */
    function calculateOtherHalf(uint reserveAmount, uint amount) onlyOwner public view returns(uint) {
        address defaultRoute = pairs[address(defaultPair)].routerAddress;
        uint half = SafeMath.sqrt(reserveAmount.mul(amount.mul(routers[defaultRoute].param1)
        .add(reserveAmount.mul(routers[defaultRoute].param2))))
        .sub(reserveAmount.mul(routers[defaultRoute].param3)) / routers[defaultRoute].param4;
        return half;
    }
    
    /**
     * @dev The owner can convert an arbitrary amount of CBK in a DEX for an equal value of LP tokens
     * @param _amount Amount of CBK to be converted to LP
     */
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
            amountHalved, 0, path, address(this), block.timestamp);
        uint CBKtoLiquidity = balanceBefore.sub(IERC20(CBK).balanceOf(address(this)));
        // 3. Mint LP tokens
        addLiquidity(CBKtoLiquidity);
    }
    
    /**
     * @dev The owner can convert an arbitrary amount of third-party tokens to CBK in a DEX
     * and convert those CBK for an equal value of LP tokens
     * @param amount Desired amount of token to be sold
     * @param amountOutMin Minimum amount of CBK to be bought
     * @param path Array of addresses where 1st position is the token to sell and last the token to buy.
     * Minimum 2 tokens, but can incude intermediary routes.
     * @param _router Address of the DEX router used
     */
    function convertTokenToCBKLP(uint amount, uint amountOutMin, address[] memory path, address _router) onlyOwner public {
        uint toLP = convertTokenToCBK(amount, amountOutMin, path, _router);
        CBKtoLP(toLP);
    }

    /**
     * @dev Approve any amount of token held by this smartcontract to be spent by spender
     * @param token Address of token.
     * @param spender Address of spender.
     * @param amount Amount in wei.
     */
    function approveToken(address token, address spender, uint amount) onlyOwner public {
        IERC20(token).approve(spender, amount);
    }
    
    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     * @param newOwner Address of the new owner.
     * DO NOT input a Contract address that does not include a function to reclaim ownership.
     * Funds will be permanently lost.
     */
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }
    
    /**
     * @dev Set default slippage value in ‰ (_slippage = 10 -> 1%).
     * @param _slippage Address of the new owner.
     */
    function setSlippage(uint _slippage) onlyOwner public {
        slippage = _slippage;
    }
    
    
    //INTERNAL

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * @param newOwner Address of the new owner.
     */
    function _transferOwnership(address newOwner) internal {
        address oldOwner = admin;
        admin = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
    
    /**
     * @dev This function is a protection against frontrunning attempts by bots when adding liquidity.
     * @return Minimum amount of CBK to add to liquidity
     * @param amountCBK Desired amount of CBK to be added
     */
    function safeMin(uint amountCBK) internal view returns(uint){
        uint _safeMin = (amountCBK*1000)/(1000+slippage);
        return _safeMin;
    }

    /**
     * @dev Add liquidity to the DEX pool.
     * @param amountCBK Desired amount of CBK to be added
     */
    function addLiquidity(uint amountCBK) internal {
        uint tokenBalance = IERC20(pairs[address(defaultPair)].token).balanceOf(address(this));
        uint minCBK = safeMin(amountCBK);
        uint minToken = safeMin(tokenBalance);
        (, , uint lpAmount) = IUniswapV2Router02(pairs[address(defaultPair)].routerAddress).addLiquidity(
        CBK, pairs[address(defaultPair)].token, amountCBK, tokenBalance, minCBK, minToken, liquidityManager, block.timestamp);
        require(lpAmount >= 1, 'insufficient LP tokens received');
    }

    /**
     * @dev This internal function buys CBK from DEX using tokens.
     * @param amountIn Desired amount of token to be sold
     * @param amountOutMin Minimum amount of token to be bought
     * @param path Array of addresses where 1st position is the token to sell and last the token to buy
     * Minimum 2 tokens, but can incude intermediary routes.
     * @param router Address of the DEX router used
     */
    function swapTokens(uint amountIn, uint amountOutMin, address[] memory path, address router) internal {
        IUniswapV2Router02(router).swapExactTokensForTokens(amountIn, amountOutMin, path, address(this), block.timestamp);
    }

    /**
     * @dev Check if a token has been converted to enough CBK
     * @param token Desired amount of CBK to be added
     */
    function checkIfFinalized(address token) internal {
        if(tokens[token].accepted == true && tokens[token].redeemedUSD >= tokens[token].price) {
            tokens[token].finalizedWithSuccess = true;
            emit FinalizedWithSuccess(token, tokens[token].converted, tokens[token].redeemedUSD, tokens[token].redeemedCBK, tokens[token].price);
        }
    }
}
