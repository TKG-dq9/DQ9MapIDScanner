const express = require("express");

const app = express();
app.use(express.json());

let scanCount = 0;

app.get("/", (req, res) => {
    res.send("DQ9 server online");
});

app.post("/scan", (req, res) => {
    scanCount++;

    const {
        fq,
        rank,
        seed,
        location,
        urls = []
    } = req.body;

    const melonGx = urls[0] || "";
    const yab = urls[1] || "";

    console.log(
        `${scanCount},${fq},${rank},${seed},${location},"${melonGx}","${yab}"`
    );

    res.sendStatus(200);
});

app.listen(3000, () => {
    console.log("Listening on port 3000");
    console.log("#, FQ, Rank, Seed, @, MelonGx, yab");
});