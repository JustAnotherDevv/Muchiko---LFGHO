"use client";

import React, { useEffect, useState } from "react";
import Link from "next/link";
import { connectorsForWallets } from "@rainbow-me/rainbowkit";
import { formatEther, formatUnits, parseEther, parseUnits } from "ethers/lib/utils";
import type { NextPage } from "next";
import { useAccount, useNetwork, useWaitForTransaction } from "wagmi";
import { BugAntIcon, MagnifyingGlassIcon } from "@heroicons/react/24/outline";
import { useScaffoldContractRead, useScaffoldContractWrite } from "~~/hooks/scaffold-eth";

const Home: NextPage = () => {
  const [rangeVal, setRangeVal] = useState(0);
  const [ghoVal, setGhoVal] = useState(0);
  const [buckets, setBuckets] = useState([]);

  const chain = useNetwork();
  const { address } = useAccount();
  const { isConnected } = useAccount();

  const { data: userBucketAmount, refetch: refetchBucketAmount } = useScaffoldContractRead({
    contractName: "Sender",
    functionName: "userBucketAmount",
    args: [address],
  });

  const { data: userBuckets, refetch: refetchBuckets } = useScaffoldContractRead({
    contractName: "Sender",
    functionName: "userBuckets",
    args: ["0x6e7F1a7d1Bac9c7784c7C7Cdb098A727F62E95c7", BigInt(0)],
  });

  const { data: btcBalance } = useScaffoldContractRead({
    contractName: "BTC",
    functionName: "balanceOf",
    args: [address],
  });

  const { data: btcValue, refetch } = useScaffoldContractRead({
    contractName: "Sender",
    functionName: "getCurrentCollateralWorth",
    args: [parseEther(rangeVal.toString())],
    // args: [1000000000000000000],
  });

  const {
    writeAsync: mintGho,
    isLoading,
    isMining,
  } = useScaffoldContractWrite({
    contractName: "Sender",
    functionName: "deposit",
    args: [parseEther(rangeVal.toString()), parseEther(ghoVal.toString())],
    // value: parseEther("0.1"),
    blockConfirmations: 1,
    onBlockConfirmation: txnReceipt => {
      console.log("Transaction blockHash", txnReceipt.blockHash);
    },
  });

  const handleRangeChange = event => {
    if (event.target.value < 1 || event.target.value > calc(formatUnits(btcBalance.toString(), 18)))
      setRangeVal(calc(formatUnits(btcBalance.toString(), 18)));
    setRangeVal(event.target.value);
  };

  const handleGhoChange = event => {
    if (event.target.value < 1 || event.target.value > calculatedGhoValue) setGhoVal(calculatedGhoValue);
    setGhoVal(event.target.value);
  };

  // const mintGho = () => {};

  const calculatedGhoValue = btcValue ? parseInt(formatUnits(btcValue.toString(), 8)) / 2 : 0;

  useEffect(() => {
    (async () => {
      console.log(isConnected, " ", address);
      if (isConnected && address) {
        await refetchBucketAmount();
        console.log(await refetchBuckets());
        // userBuckets.refetch();
      }
    })();
  }, [isConnected, address]);

  useEffect(() => {
    (async () => {
      console.log(rangeVal, " ", isConnected, " ", address);
      if (rangeVal) {
        console.log(" !!!! ");
        console.log(formatUnits((await refetch()).data.toString(), 0));
        console.log(formatUnits((await refetch()).data.toString(), 8));
        // console.log(parseInt((await refetch()).data));
      }
    })();
  }, [rangeVal]);

  function calc(amount) {
    var with2Decimals = amount.toString().match(/^-?\d+(?:\.\d{0,4})?/)[0];
    // console.log(with2Decimals);
    return with2Decimals;
  }

  return (
    <>
      <div className="flex items-center flex-col flex-grow pt-10 bg-base-300">
        <h1 className="text-center mb-8"></h1>
        <div className="px-5 flex flex-col text-center gap-8 bg-base-200 px-16 py-12 rounded-3xl">
          <span className="block text-4xl font-bold">Deposit Liquidity</span>
          {userBuckets
            ? JSON.parse(
                JSON.stringify(
                  userBuckets.data,
                  (key, value) => (typeof value === "bigint" ? value.toString() : value), // return everything else unchanged
                ),
              )
            : "empty"}
          {/* {parseInt(userBuckets)} */}
          {/* {btcBalance ? parseInt(formatUnits(btcBalance.toString(), 18)) : ""} */}
          {/* {JSON.parse(btcValue)} */}
          {/* {btcValue ? parseInt(formatUnits(btcValue.toString(), 8)) : ""} */}
          <br />
          {parseInt(userBucketAmount)}
          {/* {ghoVal} */}
          <div className="px-5 flex flex-col gap-12 mx-auto w-full">
            <div className="flex flex-col bg-base-100 px-10 py-10 text-center items-center w-full rounded-3xl">
              <BugAntIcon className="h-8 w-8 fill-secondary" />
              <p>Locked Collateral</p>
              <input
                type="range"
                min={0}
                max={btcBalance ? calc(formatUnits(btcBalance.toString(), 18)) : 0}
                value={rangeVal}
                className="range"
                step="1"
                onChange={handleRangeChange}
              />
              <p className="font-bold">MAX: {btcBalance ? calc(formatUnits(btcBalance.toString(), 18)) : 0}</p>
              <input
                type="number"
                min={0}
                max="100"
                value={rangeVal}
                onChange={handleRangeChange}
                placeholder={`MAX: ${btcBalance ? parseFloat(formatUnits(btcBalance.toString(), 18)) : 0}`}
                className="input input-bordered w-full max-w-xs mt-4"
              />
            </div>
            <div className="flex flex-col bg-base-100 px-10 py-10 text-center items-center w-full rounded-3xl">
              <BugAntIcon className="h-8 w-8 fill-secondary" />
              <p>Received GHO</p>
              <input
                type="range"
                min={0}
                max={calculatedGhoValue}
                value={ghoVal}
                className="range"
                step="1"
                onChange={handleGhoChange}
              />
              <p className="font-bold">MAX: {calculatedGhoValue ? calculatedGhoValue : 0}</p>
              <input
                type="number"
                min={0}
                max={calculatedGhoValue}
                value={ghoVal}
                onChange={handleGhoChange}
                placeholder="Type here"
                className="input input-bordered w-full max-w-xs mt-4"
              />
            </div>
          </div>
          <button className="btn btn-active btn-accent" onClick={mintGho}>
            MINT
          </button>
          <p className="text-gray-200 text-left w-full max-w-xl">
            Each bucket liquidity reduces its collateral by 1% for the Protocol's token holder rewards.
          </p>
        </div>

        <div className="flex-grow bg-base-300 w-full mt-16 px-8 pt-12">
          <div className="overflow-x-auto">
            <table className="table flex flex-col">
              {/* head */}
              <thead>
                <tr>
                  <th></th>
                  <th>Collateral</th>
                  <th>Borrowed GHO</th>
                  <th>Current Worth</th>
                </tr>
              </thead>
              <tbody className="table flex flex-col justify-middle align-center mx-auto w-full my-4">
                {buckets.length == 0 ? (
                  <div className="mx-auto w-full">
                    <p className="text-gray-200 text-left w-full max-w-xl">You haven't made any deposits so far.</p>
                  </div>
                ) : (
                  buckets.map((bucket, i) => (
                    <tr className="hover">
                      <th>2</th>
                      <td>Hart Hagerty</td>
                      <td>Desktop Support Technician</td>
                      <td>Purple</td>
                      <td>
                        <button className="btn btn-active btn-accent">RETURN</button>
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </>
  );
};

export default Home;
