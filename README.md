# Uniswap V4 on Move: My Experiment with a New Approach 🚀

Hey there! 👋 So, I’ve been diving into Uniswap V4 recently, and I thought, why not try a different approach and rewrite it in a completely different language? 🤔 That’s how I ended up deciding to rewrite this project in **Move**. It’s a language that makes resources its core concept, which is pretty different from Solidity. 🔐

Now, I’m not claiming I’m an expert, but what really caught my attention is how Move can help you write more secure contracts. 🛡️ It’s still all pretty new to me, and I’m not 100% sure if it's all as great as they say, but I figured I’d give it a shot and see for myself! 💡

One thing that stands out is how different Move feels when you work with it. From my experience, it definitely seems to push you toward writing safer contracts. 🔒 But, a little challenge here: Move doesn’t support negative values, which can make converting something like the Solidity-based Uniswap a bit tricky at times. 🤷‍♂️

I wanted to look at some other Move-based Uniswap implementations for inspiration, but... well, I couldn’t really find any. 😞 Bummer, right? But once I finished it, I thought, why not open-source it and share it with the world? 🌍 So here it is!

Now, Ethereum has **EIP-1153**, which uses transient storage for things like liquidity changes or token swaps. 🔄 Sui doesn’t quite have that feature, but it does have something interesting: when you delete data from storage, you get **99% of the storage gas fees back**. 💸 So, I used this feature to simulate EIP-1153 with a file called `currency_delta.move`. I haven’t tested it yet with cross-pool swaps, though. 🤞

The big thing with Uniswap V4 is the **hook design** 🎣 But Sui has this neat feature called **PTB** (Permissioned Transaction Block), which can achieve the same effect without needing to explicitly code hooks into the contract. So, I skipped that part for this project.

Finally, I’ll just throw this in there: I’m actively looking for a **DeFi-related job**! 💼 If you’re interested or want to chat more about this project, feel free to reach out to me at **einstellungsu@gmail.com**. 📧
