import { Generators } from "./common/ObservableStdlib.js"

import { refreshAllCompletionPromise, allCellsCompletedPromise } from "./editor.js"
import { statistics } from "./feedback.js";

function makeBond(bondNode) {
    if(bondNode.getRootNode() != document){
        return
    }
    bondNode.generator.next().value.then(val => {
        statistics.numBondSets++

        refreshAllCompletionPromise();
        window.client.sendreceive("bond_set", {
            sym: bondNode.getAttribute("def"),
            val: val,
        }).then(u => {
        })
        allCellsCompletedPromise.then(_ => {
            makeBond(bondNode)
        })
    })
}

document.addEventListener("celloutputchanged", (e) => {
    const cellNode = e.detail.cell
    const mime = e.detail.mime
    if(mime != "text/html"){
        return
    }
    const bondNodes = cellNode.querySelectorAll("bond")

    bondNodes.forEach(bondNode => {
        bondNode.generator = Generators.input(bondNode.firstElementChild)
        allCellsCompletedPromise.then(_ => {
            makeBond(bondNode)
        })
    })
}, false)
