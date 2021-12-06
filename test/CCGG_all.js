const CCGG_all = artifacts.require("CCGG_all");

contract("CCGG_all", function (accounts) {
  
  it("should assert true", async function () {
    await CCGG_all.deployed();
    return assert.isTrue(true);
  });

  dsecribe('Chainlink rng functionality', () => {

    it('calls request randomness four times when creating a new board', () => {
      // TODO
    })
    
    it('handles the "fulfillRandomness" function properly', () => {
      // TODO
    })

  })

  describe('submitting a guess', () => {

    it('dispatches the "guess submitted" event', () => {
      // TODO
    })

  })

  describe('processing a guess', () => {

    it('processes the guess...', () => {
      // TODO
    })

  })

});
