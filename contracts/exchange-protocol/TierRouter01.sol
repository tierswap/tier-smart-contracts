// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.6.6;

import "@uniswap/lib/contracts/libraries/TransferHelper.sol";

import "./libraries/TierLibrary.sol";
import "./interfaces/ITierRouter01.sol";
import "./interfaces/ITierFactory.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IWETH.sol";

contract TierRouter01 is ITierRouter01 {
	address public immutable override factory;
	address public immutable override WETH;

	modifier ensure(uint deadline) {
		require(deadline >= block.timestamp, "TierRouter: EXPIRED");
		_;
	}

	constructor(address _factory, address _WETH) public {
		factory = _factory;
		WETH = _WETH;
	}

	receive() external payable {
		assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
	}

	// **** ADD LIQUIDITY ****
	function _addLiquidity(
		address tokenA,
		address tokenB,
		uint amountADesired,
		uint amountBDesired,
		uint amountAMin,
		uint amountBMin
	) private returns (uint amountA, uint amountB) {
		// create the pair if it doesn't exist yet
		if (ITierFactory(factory).getPair(tokenA, tokenB) == address(0)) {
			ITierFactory(factory).createPair(tokenA, tokenB);
		}
		(uint reserveA, uint reserveB) = TierLibrary.getReserves(
			factory,
			tokenA,
			tokenB
		);
		if (reserveA == 0 && reserveB == 0) {
			(amountA, amountB) = (amountADesired, amountBDesired);
		} else {
			uint amountBOptimal = TierLibrary.quote(
				amountADesired,
				reserveA,
				reserveB
			);
			if (amountBOptimal <= amountBDesired) {
				require(
					amountBOptimal >= amountBMin,
					"TierRouter: INSUFFICIENT_B_AMOUNT"
				);
				(amountA, amountB) = (amountADesired, amountBOptimal);
			} else {
				uint amountAOptimal = TierLibrary.quote(
					amountBDesired,
					reserveB,
					reserveA
				);
				assert(amountAOptimal <= amountADesired);
				require(
					amountAOptimal >= amountAMin,
					"TierRouter: INSUFFICIENT_A_AMOUNT"
				);
				(amountA, amountB) = (amountAOptimal, amountBDesired);
			}
		}
	}

	function addLiquidity(
		address tokenA,
		address tokenB,
		uint amountADesired,
		uint amountBDesired,
		uint amountAMin,
		uint amountBMin,
		address to,
		uint deadline
	)
		external
		override
		ensure(deadline)
		returns (uint amountA, uint amountB, uint liquidity)
	{
		(amountA, amountB) = _addLiquidity(
			tokenA,
			tokenB,
			amountADesired,
			amountBDesired,
			amountAMin,
			amountBMin
		);
		address pair = TierLibrary.pairFor(factory, tokenA, tokenB);
		TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
		TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
		liquidity = ITierPair(pair).mint(to);
	}

	function addLiquidityETH(
		address token,
		uint amountTokenDesired,
		uint amountTokenMin,
		uint amountETHMin,
		address to,
		uint deadline
	)
		external
		payable
		override
		ensure(deadline)
		returns (uint amountToken, uint amountETH, uint liquidity)
	{
		(amountToken, amountETH) = _addLiquidity(
			token,
			WETH,
			amountTokenDesired,
			msg.value,
			amountTokenMin,
			amountETHMin
		);
		address pair = TierLibrary.pairFor(factory, token, WETH);
		TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
		IWETH(WETH).deposit{ value: amountETH }();
		assert(IWETH(WETH).transfer(pair, amountETH));
		liquidity = ITierPair(pair).mint(to);
		if (msg.value > amountETH)
			TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH); // refund dust eth, if any
	}

	// **** REMOVE LIQUIDITY ****
	function removeLiquidity(
		address tokenA,
		address tokenB,
		uint liquidity,
		uint amountAMin,
		uint amountBMin,
		address to,
		uint deadline
	) public override ensure(deadline) returns (uint amountA, uint amountB) {
		address pair = TierLibrary.pairFor(factory, tokenA, tokenB);
		ITierPair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
		(uint amount0, uint amount1) = ITierPair(pair).burn(to);
		(address token0, ) = TierLibrary.sortTokens(tokenA, tokenB);
		(amountA, amountB) = tokenA == token0
			? (amount0, amount1)
			: (amount1, amount0);
		require(amountA >= amountAMin, "TierRouter: INSUFFICIENT_A_AMOUNT");
		require(amountB >= amountBMin, "TierRouter: INSUFFICIENT_B_AMOUNT");
	}

	function removeLiquidityETH(
		address token,
		uint liquidity,
		uint amountTokenMin,
		uint amountETHMin,
		address to,
		uint deadline
	)
		public
		override
		ensure(deadline)
		returns (uint amountToken, uint amountETH)
	{
		(amountToken, amountETH) = removeLiquidity(
			token,
			WETH,
			liquidity,
			amountTokenMin,
			amountETHMin,
			address(this),
			deadline
		);
		TransferHelper.safeTransfer(token, to, amountToken);
		IWETH(WETH).withdraw(amountETH);
		TransferHelper.safeTransferETH(to, amountETH);
	}

	function removeLiquidityWithPermit(
		address tokenA,
		address tokenB,
		uint liquidity,
		uint amountAMin,
		uint amountBMin,
		address to,
		uint deadline,
		bool approveMax,
		uint8 v,
		bytes32 r,
		bytes32 s
	) external override returns (uint amountA, uint amountB) {
		address pair = TierLibrary.pairFor(factory, tokenA, tokenB);
		uint value = approveMax ? uint(-1) : liquidity;
		ITierPair(pair).permit(
			msg.sender,
			address(this),
			value,
			deadline,
			v,
			r,
			s
		);
		(amountA, amountB) = removeLiquidity(
			tokenA,
			tokenB,
			liquidity,
			amountAMin,
			amountBMin,
			to,
			deadline
		);
	}

	function removeLiquidityETHWithPermit(
		address token,
		uint liquidity,
		uint amountTokenMin,
		uint amountETHMin,
		address to,
		uint deadline,
		bool approveMax,
		uint8 v,
		bytes32 r,
		bytes32 s
	) external override returns (uint amountToken, uint amountETH) {
		address pair = TierLibrary.pairFor(factory, token, WETH);
		uint value = approveMax ? uint(-1) : liquidity;
		ITierPair(pair).permit(
			msg.sender,
			address(this),
			value,
			deadline,
			v,
			r,
			s
		);
		(amountToken, amountETH) = removeLiquidityETH(
			token,
			liquidity,
			amountTokenMin,
			amountETHMin,
			to,
			deadline
		);
	}

	// **** SWAP ****
	// requires the initial amount to have already been sent to the first pair
	function _swap(
		uint[] memory amounts,
		address[] memory path,
		address _to
	) private {
		for (uint i; i < path.length - 1; i++) {
			(address input, address output) = (path[i], path[i + 1]);
			(address token0, ) = TierLibrary.sortTokens(input, output);
			uint amountOut = amounts[i + 1];
			(uint amount0Out, uint amount1Out) = input == token0
				? (uint(0), amountOut)
				: (amountOut, uint(0));
			address to = i < path.length - 2
				? TierLibrary.pairFor(factory, output, path[i + 2])
				: _to;
			ITierPair(TierLibrary.pairFor(factory, input, output)).swap(
				amount0Out,
				amount1Out,
				to,
				new bytes(0)
			);
		}
	}

	function swapExactTokensForTokens(
		uint amountIn,
		uint amountOutMin,
		address[] calldata path,
		address to,
		uint deadline
	) external override ensure(deadline) returns (uint[] memory amounts) {
		amounts = TierLibrary.getAmountsOut(factory, amountIn, path);
		require(
			amounts[amounts.length - 1] >= amountOutMin,
			"TierRouter: INSUFFICIENT_OUTPUT_AMOUNT"
		);
		TransferHelper.safeTransferFrom(
			path[0],
			msg.sender,
			TierLibrary.pairFor(factory, path[0], path[1]),
			amounts[0]
		);
		_swap(amounts, path, to);
	}

	function swapTokensForExactTokens(
		uint amountOut,
		uint amountInMax,
		address[] calldata path,
		address to,
		uint deadline
	) external override ensure(deadline) returns (uint[] memory amounts) {
		amounts = TierLibrary.getAmountsIn(factory, amountOut, path);
		require(
			amounts[0] <= amountInMax,
			"TierRouter: EXCESSIVE_INPUT_AMOUNT"
		);
		TransferHelper.safeTransferFrom(
			path[0],
			msg.sender,
			TierLibrary.pairFor(factory, path[0], path[1]),
			amounts[0]
		);
		_swap(amounts, path, to);
	}

	function swapExactETHForTokens(
		uint amountOutMin,
		address[] calldata path,
		address to,
		uint deadline
	)
		external
		payable
		override
		ensure(deadline)
		returns (uint[] memory amounts)
	{
		require(path[0] == WETH, "TierRouter: INVALID_PATH");
		amounts = TierLibrary.getAmountsOut(factory, msg.value, path);
		require(
			amounts[amounts.length - 1] >= amountOutMin,
			"TierRouter: INSUFFICIENT_OUTPUT_AMOUNT"
		);
		IWETH(WETH).deposit{ value: amounts[0] }();
		assert(
			IWETH(WETH).transfer(
				TierLibrary.pairFor(factory, path[0], path[1]),
				amounts[0]
			)
		);
		_swap(amounts, path, to);
	}

	function swapTokensForExactETH(
		uint amountOut,
		uint amountInMax,
		address[] calldata path,
		address to,
		uint deadline
	) external override ensure(deadline) returns (uint[] memory amounts) {
		require(path[path.length - 1] == WETH, "TierRouter: INVALID_PATH");
		amounts = TierLibrary.getAmountsIn(factory, amountOut, path);
		require(
			amounts[0] <= amountInMax,
			"TierRouter: EXCESSIVE_INPUT_AMOUNT"
		);
		TransferHelper.safeTransferFrom(
			path[0],
			msg.sender,
			TierLibrary.pairFor(factory, path[0], path[1]),
			amounts[0]
		);
		_swap(amounts, path, address(this));
		IWETH(WETH).withdraw(amounts[amounts.length - 1]);
		TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
	}

	function swapExactTokensForETH(
		uint amountIn,
		uint amountOutMin,
		address[] calldata path,
		address to,
		uint deadline
	) external override ensure(deadline) returns (uint[] memory amounts) {
		require(path[path.length - 1] == WETH, "TierRouter: INVALID_PATH");
		amounts = TierLibrary.getAmountsOut(factory, amountIn, path);
		require(
			amounts[amounts.length - 1] >= amountOutMin,
			"TierRouter: INSUFFICIENT_OUTPUT_AMOUNT"
		);
		TransferHelper.safeTransferFrom(
			path[0],
			msg.sender,
			TierLibrary.pairFor(factory, path[0], path[1]),
			amounts[0]
		);
		_swap(amounts, path, address(this));
		IWETH(WETH).withdraw(amounts[amounts.length - 1]);
		TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
	}

	function swapETHForExactTokens(
		uint amountOut,
		address[] calldata path,
		address to,
		uint deadline
	)
		external
		payable
		override
		ensure(deadline)
		returns (uint[] memory amounts)
	{
		require(path[0] == WETH, "TierRouter: INVALID_PATH");
		amounts = TierLibrary.getAmountsIn(factory, amountOut, path);
		require(amounts[0] <= msg.value, "TierRouter: EXCESSIVE_INPUT_AMOUNT");
		IWETH(WETH).deposit{ value: amounts[0] }();
		assert(
			IWETH(WETH).transfer(
				TierLibrary.pairFor(factory, path[0], path[1]),
				amounts[0]
			)
		);
		_swap(amounts, path, to);
		if (msg.value > amounts[0])
			TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]); // refund dust eth, if any
	}

	function quote(
		uint amountA,
		uint reserveA,
		uint reserveB
	) public pure override returns (uint amountB) {
		return TierLibrary.quote(amountA, reserveA, reserveB);
	}

	function getAmountOut(
		uint amountIn,
		uint reserveIn,
		uint reserveOut
	) public pure override returns (uint amountOut) {
		return TierLibrary.getAmountOut(amountIn, reserveIn, reserveOut);
	}

	function getAmountIn(
		uint amountOut,
		uint reserveIn,
		uint reserveOut
	) public pure override returns (uint amountIn) {
		return TierLibrary.getAmountOut(amountOut, reserveIn, reserveOut);
	}

	function getAmountsOut(
		uint amountIn,
		address[] memory path
	) public view override returns (uint[] memory amounts) {
		return TierLibrary.getAmountsOut(factory, amountIn, path);
	}

	function getAmountsIn(
		uint amountOut,
		address[] memory path
	) public view override returns (uint[] memory amounts) {
		return TierLibrary.getAmountsIn(factory, amountOut, path);
	}
}
