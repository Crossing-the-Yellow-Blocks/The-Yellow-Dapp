const web3 = new Web3(window.ethereum);
			
const ABIF2M  ;
const ABIORACLE  ;
const ABIIERC20 ;
const ABIIUNIPAIR ;

const address_f2m = '0x0f8794f66C7170c4f9163a8498371A747114f6C4';
const address_oracle = '0x9b7b6BBd7d87e381F07484Ea104fcc6A0363DF39';
const address_cbk = '0xCfb72ED3647cC8E7FA52E4F121eCdAbEfC305e7f';
const address_usd = '0xCfb72ED3647cC8E7FA52E4F121eCdAbEfC305e7f';
const address_router = '0xCfb72ED3647cC8E7FA52E4F121eCdAbEfC305e7f';
const address_unipair = '0xCfb72ED3647cC8E7FA52E4F121eCdAbEfC305e7f';


var F2M = new web3.eth.Contract(ABIF2M, address_f2m);
var ORACLE = new web3.eth.Contract(ABIORACLE, address_oracle);
var CBK = new web3.eth.Contract(ABIIERC20, address_cbk);
var USD = new web3.eth.Contract(ABIIERC20, address_usd);
var UNIPAIR = new web3.eth.Contract(ABIIERC20, address_usd);

var user;
var admin;

var buyPercentage;
var liquidityPercentage;
var minimumReserves;

var userBalanceCBK;
var userBalanceUSD;
var usdAllowanceToF2M;


async function startWeb3() {
	await window.ethereum.enable();
    user = ethereum.selectedAddress;
    
    getAllowance(user, address_f2m);
    getUserCBK(user);
    getUserUSD(user);

}


//CALL Functions

async function getAllowance(owner, spender) {
	await USD.methods.allowance(owner, spender).call().then(r => {
		usdAllowanceToF2M = Number(r);
	});
}

async function getUserCBK(address) {
	await CBK.methods.balanceOf(address).call().then(r => {
		userBalanceCBK = Number(r);
		document.getElementById('cbk_balance').innerHTML = Number((convert(userBalanceCBK, "wei", "ether")).toFixed(3));
	});
}

async function getUserUSD(address) {
	await USD.methods.balanceOf(address).call().then(r => {
		userBalanceUSD = Number(r);
		document.getElementById('usd_balance').innerHTML = Number((convert(userBalanceUSD, "wei", "ether")).toFixed(3));
	});
}


//SEND Functions

async function buyDefault(amount) {
	await F2M.methods.buyDefault(amount).send( {from: web3.givenProvider.selectedAddress}).on('receipt', function(receipt) {
		console.log(receipt);
	});
}

async function buy(amount, slippage, deadline) {
	await F2M.methods.buy(amount, slippage, deadline).send( {from: web3.givenProvider.selectedAddress}).on('receipt', function(receipt) {
		console.log(receipt);
	});
}

async function redeem(amount) {
	await F2M.methods.redeem(amount).send( {from: web3.givenProvider.selectedAddress}).on('receipt', function(receipt) {
		console.log(receipt);
	});
}

async function redeemCommunity(address, amount) {
	await F2M.methods.redeemCommunity(address, amount).send( {from: web3.givenProvider.selectedAddress}).on('receipt', function(receipt) {
		console.log(receipt);
	});
}



async function claimIfEnded() {
	await F2M.methods.claimDeposited().send( {from: web3.givenProvider.selectedAddress}).on('receipt', function(receipt) {
		console.log(receipt);
	});
}

async function approveRouterUSD(amount) {
	await USD.methods.approve(address_router, amount).send( {from: web3.givenProvider.selectedAddress}).on('receipt', function(receipt) {
		console.log(receipt);
	});
}
	


//https://github.com/ethereumjs/ethereumjs-units
//https://eth-converter.com/extended-converter.html
BigNumber.config({EXPONENTIAL_AT: 31})

var toEther = {
	wei: "0.000000000000000001",
	kwei: "0.000000000000001",
	mwei: "0.000000000001",
	gwei: "0.000000001",
	szabo: "0.000001",
	finney: "0.001",
	ether: "1",
	kether: "1000",
	mether: "1000000",
	gether: "1000000000",
	tether: "1000000000000"
};

var scale = {
	wei: "1000000000000000000",
	kwei: "1000000000000000",
	mwei: "1000000000000",
	gwei: "1000000000",
	szabo: "1000000",
	finney: "1000",
	ether: "1",
	kether: "0.001",
	mether: "0.000001",
	gether: "0.000000001",
	tether: "0.000000000001"
};

function update() {

		startWeb3();
}

function convert(e, t, n) {
	var i = new BigNumber(e);
	return (i = i.times(new BigNumber(toEther[t]))).times(new BigNumber(scale[n]));
}

//Format a bignumber to display correctly
function format(bignumber) {
	fmt = {
		decimalSeparator: '.',
		groupSeparator: ','
	}

	if (bignumber.isGreaterThanOrEqualTo(1000000)) {
		return bignumber.div(1000000).toFormat(2, fmt).replace('.00', '') + 'M';
	} else if (bignumber.isGreaterThanOrEqualTo(1000)) {
		return bignumber.div(1000).toFormat(2, fmt).replace('.00', '') + 'm';
	} else {
		return bignumber.toFormat(2, fmt).replace('.00', '');
	}
}


window.onload = update();
