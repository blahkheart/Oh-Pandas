const ethers = require('ethers')

const runIt = async () => {
    const provider = new ethers.providers.JsonRpcProvider("https://goerli.infura.io/v3/988a82bfe0a540ad84aa1a5d534c2bc6")
    const wallet = new ethers.Wallet.fromMnemonic("reveal miracle slice fever frown insect genuine faculty ignore focus forget inspire")
    const signer = wallet.connect(provider)

    const tx = signer.sendTransaction({
        to: "0xCA7632327567796e51920F6b16373e92c7823854",
        value: ethers.utils.parseEther("0.11")
    })
    console.log(tx.hash)
}

runIt()