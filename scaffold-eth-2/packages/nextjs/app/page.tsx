"use client";

import React, { useEffect, useState } from "react";
import Link from "next/link";
import { connectorsForWallets } from "@rainbow-me/rainbowkit";
import { formatEther, formatUnits, parseEther } from "ethers/lib/utils";
import type { NextPage } from "next";
import { useAccount, useNetwork, useWaitForTransaction } from "wagmi";
import { BugAntIcon, MagnifyingGlassIcon } from "@heroicons/react/24/outline";
import { useScaffoldContractRead } from "~~/hooks/scaffold-eth";

const Home: NextPage = () => {
  const [rangeVal, setRangeVal] = useState(1);
  const [ghoVal, setGhoVal] = useState(5);
  const [buckets, setBuckets] = useState([]);

  const chain = useNetwork();
  const { address } = useAccount();
  const { isConnected } = useAccount();

  const { data: userBuckets, refetch } = useScaffoldContractRead({
    contractName: "Sender",
    functionName: "userBuckets",
    args: [address, BigInt(0)],
  });

  const { data: btcBalance } = useScaffoldContractRead({
    contractName: "BTC",
    functionName: "balanceOf",
    args: [address],
  });

  const handleRangeChange = event => {
    if (event.target.value < 1 || event.target.value > calc(formatUnits(btcBalance.toString(), 18))) return;
    setRangeVal(event.target.value);
  };

  const handleGhoChange = event => {
    if (event.target.value < 1 || event.target.value > 100) return;
    setGhoVal(event.target.value);
  };

  const calculatedGhoValue = rangeVal / 2;

  useEffect(() => {
    (async () => {
      console.log(isConnected, " ", address);
      if (isConnected && address) {
        console.log(await refetch());
        userBuckets.refetch();
      }
    })();
  }, [isConnected, address]);

  function calc(theform) {
    var num = theform;
    var with2Decimals = num.toString().match(/^-?\d+(?:\.\d{0,3})?/)[0];
    console.log(with2Decimals);
    return with2Decimals;
  }

  return (
    <>
      <div className="flex items-center flex-col flex-grow pt-10">
        <h1 className="text-center mb-8"></h1>
        <div className="px-5 flex flex-col text-center gap-8 bg-base-300 px-16 py-12 rounded-3xl">
          <span className="block text-4xl font-bold">Deposit Liquidity</span>
          {/* {userBuckets
            ? JSON.parse(
                JSON.stringify(
                  userBuckets,
                  (key, value) => (typeof value === "bigint" ? value.toString() : value), // return everything else unchanged
                ),
              )
            : "empty"} */}
          {/* {parseInt(userBuckets)} */}
          {btcBalance ? parseInt(formatUnits(btcBalance.toString(), 18)) : ""}
          <div className="px-5 flex flex-col gap-12 mx-auto w-full">
            <div className="flex flex-col bg-base-100 px-10 py-10 text-center items-center w-full rounded-3xl">
              <BugAntIcon className="h-8 w-8 fill-secondary" />
              <p>Locked Collateral</p>
              <p className="font-bold">MAX: {btcBalance ? calc(formatUnits(btcBalance.toString(), 18)) : 0}</p>
              <input
                type="range"
                min={0}
                max={btcBalance ? calc(formatUnits(btcBalance.toString(), 18)) : 0}
                value={rangeVal}
                className="range"
                step="1"
                onChange={handleRangeChange}
              />
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
          <button className="btn btn-active btn-accent">MINT</button>
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
