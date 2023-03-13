import {cat_def, extr_def, protex_window,
        protex_state, html_nub, op} from "./protex_renderer_include";

const ProtexWindow = window as unknown as protex_window;

function Declare<T>(): T
{
    return {} as T;
}

function Assert(ExprTruthiness: boolean, DEBUGMsg: string): void
{
    if (!ExprTruthiness)
    {
        const DEBUGTextInfoElem = TryGetElementByID("debug-text-info");
        const PrevDEBUGTextInfo = DEBUGTextInfoElem.innerText;

        DEBUGTextInfoElem.innerText = "Assert Fail: " + DEBUGMsg;
        setTimeout(() => {DEBUGTextInfoElem.innerText = PrevDEBUGTextInfo; }, 3000);

        throw DEBUGMsg;
    }
}

function OperationQueueFromLeaf(OpBoxes: HTMLCollectionOf<Element>, LeafOpBox: Element): op[]
{
    let NewOperationQueue = []
    let CurrOpBox = LeafOpBox;
    let FoundRoot = false;
    while (!FoundRoot)
    {
        const SelectTypeSelect = TryGetElementByClassName(
            CurrOpBox, "select-type-select") as HTMLSelectElement;

        let NewOp = Declare<op>();
        switch(Number(SelectTypeSelect.value))
        {
            case 0: // TODO(cjb) FIXME capture
            {
                const PatternSelect = TryGetElementByClassName(
                    CurrOpBox, "pattern-select") as HTMLSelectElement;
                Assert(PatternSelect.value !== "", "PatternSelect was empty.");
                NewOp = {Pattern: PatternSelect.value};

            } break;
            case 1: // TODO(cjb) FIXME script
            {
                const ScriptSelect = TryGetElementByClassName(
                    CurrOpBox, "script-select") as HTMLSelectElement;
                Assert(ScriptSelect.value !== "", "ScriptSelect was empty.");
                NewOp = {PyModule: ScriptSelect.value};
            } break;
            default:
            {
                Assert(false, "Fell through selector type options switch.");
            } break;
        }
        NewOperationQueue.push(NewOp);

        // Move to parent op box

        const [_, CurrRightNub] = NubsFromContainer(CurrOpBox);
        Assert(((CurrRightNub.LineIndices.length === 1) ||
                (CurrRightNub.LineIndices.length === 0)), "Expected length of 1 or 0");

        if (CurrRightNub.LineIndices.length === 0)
        {
            FoundRoot = true;
        }
        else
        {
            CurrOpBox = OpBoxFromRightLineIndex(OpBoxes,
                CurrRightNub.LineIndices[0]) as Element;
        }
    }

    return NewOperationQueue;
}

function OpBoxFromRightLineIndex(
    OpBoxes: HTMLCollectionOf<Element>, RightLineIndex: number): Element | undefined
{
    for (const Box of OpBoxes)
    {
        const [LeftNub, _] = NubsFromContainer(Box);
        for (const LeftLineIndex of LeftNub.LineIndices)
        {
            if (RightLineIndex === LeftLineIndex)
            {
                return Box;
            }
        }
    }
    Assert(false, `No LeftLineIndex matching ${RightLineIndex}`);
}

function NubsFromContainer(Container: Element): [html_nub, html_nub]
{
    const LeftNub = TryGetElementByClassName(
        Container, "draggable-container-connecter-left") as html_nub;
    const RightNub = TryGetElementByClassName(
        Container, "draggable-container-connecter-right") as html_nub;

    return [LeftNub, RightNub];
}

function LineIndexFromNub(Nub: Element): number
{
    let Result = Number(Nub.getAttribute("LineIndex"));
    return Result;
}

function RemoveSVGLineByIndex(TargetLineIndex: number): void
{
    const CategoryContainer = TryGetElementByID("category-container");
    const OpBoxes = CategoryContainer.getElementsByClassName("draggable-container");
    if ((TargetLineIndex >= 0) &&
        (TargetLineIndex < OpBoxes.length))
    {
        let FoundTargetIndex = false;

        function RemoveLineIndexFromNub(Nub: html_nub): void
        {
            const IndexToRemove = Nub.LineIndices.indexOf(TargetLineIndex);
            if (IndexToRemove !== -1)
            {
                Nub.LineIndices.splice(IndexToRemove, 1);
                FoundTargetIndex = true;
            }
        }

        // First remove indices from both boxes

        for (const Box of OpBoxes)
        {
            const [LeftNub, RightNub] = NubsFromContainer(Box);
            RemoveLineIndexFromNub(LeftNub);
            RemoveLineIndexFromNub(RightNub);
        }

        // Now update the indicies of nubs if their index is > than the removed index.

        if (FoundTargetIndex)
        {
            for (const Box of OpBoxes)
            {
                const [LeftNub, RightNub] = NubsFromContainer(Box);

                for (let [LineIndexIndex, LineIndex] of LeftNub.LineIndices.entries())
                {
                    if (LineIndex > TargetLineIndex)
                    {
                        LeftNub.LineIndices[LineIndexIndex] -= 1;
                    }
                }
                for (let [LineIndexIndex, LineIndex] of RightNub.LineIndices.entries())
                {
                    if (LineIndex > TargetLineIndex)
                    {
                        RightNub.LineIndices[LineIndexIndex] -= 1;
                    }
                }
            }
        }

        // Lastly remove the actual SVG line from the DOM.

        const SVGCategoryMask = TryGetElementByID("svg-category-mask");
        SVGCategoryMask.children[TargetLineIndex].remove()
    }
    else
    {
        Assert(false, `TargetLineIndex: ${TargetLineIndex} out of bounds.`);
    }
}

function MakeDraggableLine(ConnecterNub: html_nub): void
{
    const CategoryContainer = TryGetElementByID("category-container");
    const SVGCategoryMask = TryGetElementByID("svg-category-mask");

    let ConnecterLine: SVGLineElement;

    ConnecterNub.onmousedown = DragMouseDown;

    function DragMouseDown(E: MouseEvent): void
    {
        E = E || window.event;
        const X = E.clientX - CategoryContainer.offsetLeft;
        const Y = E.clientY - CategoryContainer.offsetTop;

        while (ConnecterNub.LineIndices.length > 0)
        {
            RemoveSVGLineByIndex(ConnecterNub.LineIndices[0]);
        }

        ConnecterLine = document.createElementNS("http://www.w3.org/2000/svg", "line");
        ConnecterLine.setAttribute("x1", `${X}`);
        ConnecterLine.setAttribute("y1", `${Y}`);
        ConnecterLine.setAttribute("x2", `${X}`);
        ConnecterLine.setAttribute("y2", `${Y}`);
        ConnecterLine.setAttribute("stroke-width", "2");
        ConnecterLine.setAttribute("stroke", "white");
        SVGCategoryMask.appendChild(ConnecterLine);

        document.onmouseup = EndLineDrag;
        document.onmousemove = ElementDrag;
    }

    function ElementDrag(E: MouseEvent)
    {
        E = E || window.event;
        E.preventDefault();

        const X = E.clientX - CategoryContainer.offsetLeft;
        const Y = E.clientY - CategoryContainer.offsetTop;

        ConnecterLine.setAttribute("x2", `${X}`);
        ConnecterLine.setAttribute("y2", `${Y}`);
    }

    function EndLineDrag(ME: MouseEvent): void
    {
        ME.preventDefault();

        document.onmouseup = null;
        document.onmousemove = null;

        // Validate line connection before it is finalized.

        const TargetNub = ME.target as html_nub | null;
        if (TargetNub !== null)
        {
            if ((ConnecterNub.parentElement !== TargetNub.parentElement) &&
                ((TargetNub.className === "draggable-container-connecter-left") &&
                 (ConnecterNub.className === "draggable-container-connecter-right")) ||
                ((TargetNub.className === "draggable-container-connecter-right") &&
                 (ConnecterNub.className === "draggable-container-connecter-left")))
            {
                const nSVGLines = document.getElementsByTagName("line").length;
                Assert(nSVGLines > 0, "nSVG lines was 0");

                TargetNub.LineIndices.push(nSVGLines - 1);
                ConnecterNub.LineIndices.push(nSVGLines - 1);

                return;
            }
        }

        ConnecterLine.remove();
    }
}

function MakeDraggable(Elmnt: HTMLElement): void
{
    const CategoryContainer = TryGetElementByID("category-container");
    const SVGCategoryMask = TryGetElementByID("svg-category-mask");
    const ContainerHeader = TryGetElementByClassName(Elmnt, "draggable-container-header", 0);

    let Pos1 = 0, Pos2 = 0, Pos3 = 0, Pos4 = 0;
    ContainerHeader.onmousedown = DragMouseDown;

    function DragMouseDown(E: MouseEvent)
    {
        E = E || window.event;
        E.preventDefault();

        Pos3 = E.clientX;
        Pos4 = E.clientY;

        document.onmouseup = CloseDragElement;
        document.onmousemove = ElementDrag;
    }

    function ElementDrag(E: MouseEvent)
    {
        E = E || window.event;
        E.preventDefault();

        // Calculate the new cursor position:

        Pos1 = Pos3 - E.clientX;
        Pos2 = Pos4 - E.clientY;
        Pos3 = E.clientX;
        Pos4 = E.clientY;

        // Set the element's new position:

        Elmnt.style.left = (Elmnt.offsetLeft - Pos1) + "px";
        Elmnt.style.top = (Elmnt.offsetTop - Pos2) + "px";

        // Also remember to draw lines at new position

        const [LeftNub, RightNub] = NubsFromContainer(Elmnt);

        for (const LineIndex of LeftNub.LineIndices)
        {
            const Line = SVGCategoryMask.children[LineIndex] as HTMLElement;
            Line.setAttribute("x2", `${Elmnt.offsetLeft - Pos1 + LeftNub.offsetLeft}`);
            Line.setAttribute("y2", `${Elmnt.offsetTop - Pos2 + LeftNub.offsetTop}`);
        }
        for (const LineIndex of RightNub.LineIndices)
        {
            const Line = SVGCategoryMask.children[LineIndex] as HTMLElement;
            Line.setAttribute("x1", `${Elmnt.offsetLeft - Pos1 + RightNub.offsetLeft}`);
            Line.setAttribute("y1", `${Elmnt.offsetTop - Pos2 + RightNub.offsetTop}`);
        }
    }

    function CloseDragElement()
    {
        // Stop moving when mouse button is released:

        document.onmouseup = null;
        document.onmousemove = null;
    }
}

function NewCatFields(ScriptNames: string[], Name: string, Conditions: string): void
{
    const CategoryContainer = TryGetElementByID("category-container");

    const DraggableContainer = document.createElement("div");
    DraggableContainer.className = "draggable-container";
    CategoryContainer.appendChild(DraggableContainer);

    const DraggableContainerHeader = document.createElement("div");
    DraggableContainerHeader.className = "draggable-container-header";
    DraggableContainer.appendChild(DraggableContainerHeader);

    const RightNub = document.createElement("span") as html_nub;
    RightNub.className = "draggable-container-connecter-right";
    RightNub.LineIndices = [];
    DraggableContainer.appendChild(RightNub);
    MakeDraggableLine(RightNub);

    const LeftNub = document.createElement("span") as html_nub;
    LeftNub.className = "draggable-container-connecter-left";
    LeftNub.LineIndices = [];
    DraggableContainer.appendChild(LeftNub);
    MakeDraggableLine(LeftNub);

    MakeDraggable(DraggableContainer);

    // Remove a box by right clicking on it

    DraggableContainer.onauxclick = (E: MouseEvent) =>
    {
        E.stopImmediatePropagation();
        E.preventDefault();

        while(LeftNub.LineIndices.length > 0)
        {
            RemoveSVGLineByIndex(LeftNub.LineIndices[0]);
        }

        while(RightNub.LineIndices.length > 0)
        {
            RemoveSVGLineByIndex(RightNub.LineIndices[0]);
        }

        DraggableContainer.remove();
    };


    const DraggableContainerContents = document.createElement("div");
    DraggableContainerContents.className = "draggable-container-contents";
    DraggableContainer.appendChild(DraggableContainerContents);

    const SelectTypeSelect = document.createElement("select");
    SelectTypeSelect.className = "select-type-select";
    DraggableContainerContents.appendChild(SelectTypeSelect);

    const PatternSelect = document.createElement("select");
    PatternSelect.className = "pattern-select";
    PatternSelect.onfocus = () =>
    {
        PatternSelect.innerHTML = "";
        const PatternsContainer = TryGetElementByID("patterns-container");
        for (const Elem of PatternsContainer.getElementsByClassName("pattern-input"))
        {
            const NewOption = document.createElement("option");
            NewOption.text = (Elem as HTMLInputElement).value;
            NewOption.value = (Elem as HTMLInputElement).value;
            PatternSelect.add(NewOption);
        }
    }
    PatternSelect.style.display = "none";
    DraggableContainerContents.appendChild(PatternSelect);

    const OffsetSlider = document.createElement("input");
    OffsetSlider.className = "capture-offset-slider";
    OffsetSlider.setAttribute("type", "range");
    OffsetSlider.setAttribute("min", "0");
    OffsetSlider.setAttribute("max", "500");
    OffsetSlider.setAttribute("value", "0");
    OffsetSlider.setAttribute("step", "10");
    OffsetSlider.style.display = "none";
    OffsetSlider.oninput = () =>
    {
        HighlightCapture(PatternSelect.value, Number(OffsetSlider.value));
    };

    for (const Elem of [DraggableContainer, DraggableContainerHeader, DraggableContainerContents])
    {
        Elem.onmouseover = () =>
        {
            if (SelectTypeSelect.value === "0")
            {
                HighlightCapture(PatternSelect.value, Number(OffsetSlider.value));
            }
        };

        Elem.onmouseout = () =>
        {
            const LSPI = LastSelectedPatternInput();
            if (LSPI != null)
            {
                HighlightCapture(LSPI.value);
            }
        };
    }

    DraggableContainerContents.appendChild(OffsetSlider);

    const ScriptSelect = document.createElement("select");
    ScriptSelect.className = "script-select";
    ScriptSelect.onfocus = () =>
    {
        ScriptSelect.innerHTML = "";
        for (const ScriptName of ScriptNames)
        {
            const NewOption = document.createElement("option");
            NewOption.text = ScriptName;
            NewOption.value = ScriptName;
            ScriptSelect.add(NewOption);
        }
    }
    ScriptSelect.style.display = "none";
    DraggableContainerContents.appendChild(ScriptSelect);

    const SelectorTypeOptions = ["Capture", "Script"];
    for (const Entry of SelectorTypeOptions.entries())
    {
        const OptionIndex = Entry[0];
        const OptionText = Entry[1];

        const NewOption = document.createElement("option");
        NewOption.text = OptionText;
        NewOption.value = OptionIndex.toString();
        SelectTypeSelect.add(NewOption);
    }
    SelectTypeSelect.selectedIndex = -1;

    SelectTypeSelect.onchange = () =>
    {
        const SelectedIndex = SelectTypeSelect.selectedIndex;
        if ((SelectedIndex >= 0) &&
            (SelectedIndex < SelectTypeSelect.options.length))
        {
            const SelectorTypeOptionsIndex = Number(SelectTypeSelect.value);
            switch(SelectorTypeOptions[SelectorTypeOptionsIndex])
            {
                case "Capture":
                {
                    PatternSelect.style.display = "block";
                    OffsetSlider.style.display = "block";

                    ScriptSelect.style.display = "none";
                } break;
                case "Script":
                {
                    ScriptSelect.style.display = "block";

                    PatternSelect.style.display = "none";
                    OffsetSlider.style.display = "none";
                } break;
                default:
                {
                    Assert(false, "Fell through selector type options switch.");
                } break;
            }
        }
    }

}

function AddEmptyCat(ScriptNames: string[], ExtrDef: extr_def): void
{
    AddCat(ScriptNames, ExtrDef, "", "");
}

//TODO(cjb): Get category/conditions in toolbar as well.
function AddCat(ScriptNames: string[], ExtrDef: extr_def, Name: string, Conditions: string): void
{
    let Cat = {
        Name: Name,
        Conditions: Conditions,
    };
    ExtrDef.Categories.push(Cat);
    NewCatFields(ScriptNames, Name, Conditions);
}

function LastSelectedPatternInput(): HTMLInputElement | null
{
    const PatternInputs = document.getElementsByClassName("pattern-input");
    for (const Elem of PatternInputs)
    {
        if ((Elem.getAttribute("IsSelected") as string) == "true")
            return (Elem as HTMLInputElement);
    }
    return null;
}

function HighlightCapture(RePattern: string, SliderOffset: number = 0): void
{
    const TextAreaText = (TryGetElementByID("text-area") as HTMLTextAreaElement).value;
    const PreText = TryGetElementByID("pre-text");
    let SpanifiedText = "";
    let Offset = 0;
    const Re = RegExp(RePattern, "gi"); //TODO(cjb): What flags do I pass here?
    let Matches: RegExpExecArray | null;
    while ((Matches = Re.exec(TextAreaText)) !== null)
    {
        const Match = Matches[0];
        const SO = Re.lastIndex - Match.length;
        const EO = Re.lastIndex;
        const LHS = TextAreaText.substring(Offset, SO);
        const RHS = '<span class="noice">' + TextAreaText.substring(SO, EO + SliderOffset) + '</span>';

        SpanifiedText += LHS + RHS;
        Offset = EO + SliderOffset;

        break;
    }
	SpanifiedText += TextAreaText.substring(Offset);
    PreText.innerHTML = SpanifiedText;
}

function UpdateSelectedPattern(TargetPatternInput: HTMLInputElement): void
{
    const PrevSelectedPatternInput = LastSelectedPatternInput();
    if (PrevSelectedPatternInput != null)
    {
        PrevSelectedPatternInput.setAttribute("IsSelected", "false");
    }
    TargetPatternInput.setAttribute("IsSelected", "true");
    HighlightCapture(TargetPatternInput.value);
}

function AddPattern(Pattern: string): void
{
    const PatternsContainer = TryGetElementByID("patterns-container");

    const PatternEntry = document.createElement("div");
    PatternEntry.className = "pattern-entry";
    PatternsContainer.appendChild(PatternEntry);

    const PatternInput = document.createElement("input");
    PatternInput.className = "pattern-input";
    PatternInput.setAttribute("IsSelected", "false");
    PatternInput.value = Pattern;
    PatternInput.addEventListener("focus", () => UpdateSelectedPattern(PatternInput));
    PatternInput.addEventListener("input", () => UpdateSelectedPattern(PatternInput));
    PatternEntry.appendChild(PatternInput);

    const RemovePatternButton = document.createElement("button");
    RemovePatternButton.className = "pattern-entry-button";
    RemovePatternButton.innerText = "-";
    RemovePatternButton.onclick = () =>
    {
        PatternEntry.remove();
    }
    PatternEntry.appendChild(RemovePatternButton);
}

function AddExtrSelectOption(ExtrName: string): void
{
    const ExtractorSelect = TryGetElementByID("extractor-select") as HTMLSelectElement;
    for (const Option of ExtractorSelect.options)
    {
        if (Option.value === "New Extractor")
        {
            Option.remove();
            break;
        }
    }

    // Add the created extractor

    const ExtractorOption = document.createElement("option");
    ExtractorOption.text = ExtrName;
    ExtractorOption.value = ExtrName;
    ExtractorSelect.add(ExtractorOption);

    // Add back "New Extractor" option

    const AddExtractorOption = document.createElement("option");
    AddExtractorOption.text = "New Extractor";
    AddExtractorOption.value = "New Extractor";
    ExtractorSelect.add(AddExtractorOption);

    // Now select new option

    let OptionIndex = 0;
    for (let Option of ExtractorSelect.options)
    {
        if (Option.value === ExtrName)
        {
            ExtractorSelect.selectedIndex = OptionIndex;
        }
        OptionIndex += 1;
    }
}

function AddEmptyExtr(Extrs: extr_def[], ExtrName: string): void
{
    AddExtr(Extrs, ExtrName, [], []);
}

function AddExtr(Extrs: extr_def[], ExtrName: string, Patterns: string[], Cats: cat_def[]): void
{
    AddExtrSelectOption(ExtrName);
    Extrs.push({
        Name: ExtrName,
        Categories: Cats.slice(0),
        Patterns: Patterns.slice(0),
    });
}

function PopulatePyModuleSelectOptions(ScriptNames: string[], Selector: HTMLSelectElement,
    SelectText: string): void
{
    Selector.innerText = "";

    const PyEntries = S.ScriptNames;
    let SelectIndex = -1;
    PyEntries.forEach((PyModule, PyModuleIndex) =>
    {
        const PyModuleNameOption = document.createElement("option");
        PyModuleNameOption.value = PyModule;
        PyModuleNameOption.text = PyModule;
        if (PyModule === SelectText)
        {
            SelectIndex = PyModuleIndex;
        }
        Selector.add(PyModuleNameOption);
    });

    const AddScriptButton = document.createElement("option");
    AddScriptButton.text = "New Script";
    AddScriptButton.value = "New Script";
    Selector.add(AddScriptButton);

    Selector.selectedIndex = SelectIndex;
}

function TryGetElementByClassName(ParentElem: Element, ClassName: string,
    Index: number = 0): HTMLElement
{
    const Elem = ParentElem.getElementsByClassName(ClassName)
        .item(Index) as HTMLElement | null;
    if (Elem == null)
    {
        throw `Couldn't get element with class: '${ClassName}' at index: '${Index}'`;
    }
    return Elem;
}

function TryGetElementByID(ElemId: string): HTMLElement
{
    const Elem = document.getElementById(ElemId);
    if (Elem == null)
    {
        throw `Couldn't get element with id: '${ElemId}'`;
    }
    return Elem;
}

function ImportJSONConfig(S: protex_state, E: Event): void
{
    if ((E.target == null) ||
        ((E.target as HTMLElement).id != "import-config-input"))
    {
        throw "Bad event target";
    }

    // Get first file ( should  only be one anyway )

    const Files = ((E.target as HTMLInputElement).files as FileList);
    if (Files.length == 0)
    {
        return;
    }
    Files[0].text().then(Text =>
    {
        S.Extractors = [];
        const ExtractorSelect = TryGetElementByID("extractor-select") as HTMLSelectElement;
        ExtractorSelect.innerHTML = "";

        const JSONConfig = JSON.parse(Text);
        let ExtrDefIndex = 0;
        for (const ExtrDef of JSONConfig.ExtractorDefinitions)
        {
            if (ExtrDefIndex === 0)
            {
                AddExtr(S.Extractors, ExtrDef.Name, ExtrDef.Patterns, ExtrDef.Categories);
                for (const Cat of ExtrDef.Categories)
                {
                    AddCat(S.ScriptNames, S.Extractors[ExtrDefIndex], Cat.Name, Cat.Conditions);
                }

                for (const P of ExtrDef.Patterns)
                {
                    AddPattern(P);
                }
            }
            else
            {
                S.Extractors.push({
                    Name: ExtrDef.Name,
                    Categories: ExtrDef.Categories.slice(0),
                    Patterns: ExtrDef.Patterns.slice(0)
                });
            }

            ExtrDefIndex += 1;
        }

        const AddExtractorOption = document.createElement("option");
        AddExtractorOption.text = "New Extractor";
        AddExtractorOption.value = "New Extractor";
        ExtractorSelect.add(AddExtractorOption);
        ExtractorSelect.selectedIndex = -1;
    });
}

function GenJSONConfig(Extractors: extr_def[]): string
{
    let CurrentExtractor = (TryGetElementByID("extractor-select") as HTMLSelectElement).value;
    let ExtrDefs: extr_def[] = [];
    Extractors.map((ExtrDef) =>
    {
        if (ExtrDef.Name === CurrentExtractor) // Use DOM elements
        {
            ExtrDef.Patterns = [];
            const PatternsContainer = TryGetElementByID("patterns-container");
            for (const Elem of PatternsContainer.getElementsByClassName("pattern-input"))
            {
                ExtrDef.Patterns.push((Elem as HTMLInputElement).value);
            }

            const CategoryContainer = TryGetElementByID("category-container");

            let LastOpBoxIndex: number = -1;
            let BoxIndex: number = 0;
            const OpBoxes = CategoryContainer.getElementsByClassName("draggable-container");
//            for (const Box of OpBoxes)
//            {
//                const [LeftNub, RightNub] = NubsFromContainer(Box);
//
//                if (RightNub.LineIndices.length === 0)
//                {
//                    if (LeftNub.LineIndices.length === 0)
//                    {
//                        Assert(false, "Box with no connections");
//                    }
//
//                    if (LastOpBoxIndex !== -1)
//                    {
//                        Assert(false, "Found multiple end paths.");
//                    }
//
//                    LastOpBoxIndex = BoxIndex;
//                }
//
//                BoxIndex += 1;
//            }
//            Assert(LastOpBoxIndex !== -1, "No valid starting op box.");

            let Operations: op[][] = [];
            for (const OpBox of OpBoxes)
            {
                const [LeftNub, _] = NubsFromContainer(OpBox);
                if (LeftNub.LineIndices.length === 0)
                {
                    Operations.push(OperationQueueFromLeaf(OpBoxes, OpBox));
                }
            }

            console.log(Operations);

            //ExtrDef.Categories = [];
            //ExtrDef.Categories.push({
            //    Name: "DEBUGNAME",
            //    Conditions: JSON.stringify(ConditionsJSON),
            //});
        }
    });

    return JSON.stringify({});
}

function EscapeRegex(Regex: string): string
{
    // NOTE(cjb): $& = whole matched string
    return Regex.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function RegexCaptureAnyNum(Regex: string): string
{
    return Regex.replace(/[\d]/g, "\\d");
}

function Regexify(Str: string): string
{
    return RegexCaptureAnyNum(EscapeRegex(Str.toLowerCase()));
}

function RegexifyLiteral(Str: string): string
{
    return EscapeRegex(Str.toLowerCase());
}

async function GetUserInput(): Promise<string>
{
    function FinishedInput(InputElem: HTMLInputElement): Promise<void>
    {
        return new Promise<void>((Resolve) => {
            InputElem.onkeyup = (E: KeyboardEvent) => {
                if (E.key === "Enter")
                {
                    Resolve();
                }
                else if (E.key === "Escape")
                {
                    InputElem.value = "";
                    Resolve();
                }
            }
        });
    }

    return new Promise<string>((Resolve) => {
        const UserInput = document.createElement("input");
        UserInput.className = "user-prompt";
        document.body.appendChild(UserInput);
        UserInput.focus();
        FinishedInput(UserInput).then(() =>
        {
            const Result = UserInput.value;
            UserInput.remove();
            Resolve(Result);
        });
    });
}

const ConfName = "webs_conf.json"; //TODO(cjb): Make this a texbox

//
// Initialization
//

let S = {} as protex_state;
S.Extractors = [];
S.ScriptNames = [];

ProtexWindow.ProtexAPI.GetScriptNames()
    .then((Result: string[]) =>
{
    S.ScriptNames = Result.slice(0);

    // Root container to add dom elements to.

    const AContainer = TryGetElementByID("a-container");

    const ToolbarContainer = document.createElement("div");
    ToolbarContainer.id = "toolbar-container";
    AContainer.appendChild(ToolbarContainer);

    // Import existing configuration input

    const ImportConfigInput = document.createElement("input");
    ImportConfigInput.id = "import-config-input";
    ImportConfigInput.setAttribute("accept", ".json");
    ImportConfigInput.type = "file";
    ImportConfigInput.style.display = "none";
    ImportConfigInput.onchange = (E) => ImportJSONConfig(S, E);
    ToolbarContainer.appendChild(ImportConfigInput);

    const ImportConfigTab = document.createElement("div");
    ImportConfigTab.tabIndex = 0;
    ImportConfigTab.className = "toolbar-item";
    ImportConfigTab.onkeypress = (E: KeyboardEvent) =>
    {
        if (E.key === "Enter")
        {
            ImportConfigInput.click()
        }
    };
    ImportConfigTab.onclick = () => ImportConfigInput.click();
    ImportConfigTab.innerText = "Import";
    ToolbarContainer.appendChild(ImportConfigTab);

    const RunExtractorButton = document.createElement("button");
    RunExtractorButton.style.display = "none";
    RunExtractorButton.onclick = () =>
    {
        // Make sure to save script in TA

        const ScriptName = ScriptEditingTA.getAttribute("name");
        if (ScriptName !== null)
        {
            ProtexWindow.ProtexAPI.WriteScript((ScriptName as string), ScriptEditingTA.value);
        }

        const ConfigStr = GenJSONConfig(S.Extractors);
        ProtexWindow.ProtexAPI.WriteConfig(ConfigStr).then(() =>
        {
            ProtexWindow.ProtexAPI.RunExtractor(ConfName, TA.value)
                .then((ExtractorOut: any) =>
            {
                console.log(ExtractorOut);
            });
        });
    }
    ToolbarContainer.appendChild(RunExtractorButton);

    const RunExtractorTab = document.createElement("div");
    RunExtractorTab.onkeypress = (E: KeyboardEvent) =>
    {
        if (E.key === "Enter")
        {
            RunExtractorButton.click()
        }
    };
    RunExtractorTab.onclick = () => RunExtractorButton.click();
    RunExtractorTab.tabIndex = 0;
    RunExtractorTab.className = "toolbar-item";
    RunExtractorTab.innerText = "Run";
    ToolbarContainer.appendChild(RunExtractorTab);

    const ActiveScriptSelect = document.createElement("select");
    let PrevSelectedScriptIndex = -1;
    ActiveScriptSelect.onchange = () => {
        let NewScriptName = ActiveScriptSelect.value;
        if (NewScriptName === "New Script")
        {
            GetUserInput().then((Result) => {
                NewScriptName = Result;

                if (NewScriptName === "")
                {
                    // Make selected option nothing if it's just new script option.

                    ActiveScriptSelect.selectedIndex = PrevSelectedScriptIndex;
                    return;
                }
                PrevSelectedScriptIndex = ActiveScriptSelect.selectedIndex;

                ScriptEditingTA.value =
                    `def protex_main(text: str, so: int, eo: int) -> str:\n    return ""`;
                ScriptEditingTA.setAttribute("name", NewScriptName);
                ProtexWindow.ProtexAPI.WriteScript(NewScriptName, ScriptEditingTA.value)
                    .then(() =>
                {
                    ProtexWindow.ProtexAPI.GetScriptNames()
                        .then((Result: string[]) =>
                    {
                        S.ScriptNames = Result.slice(0);
                        PopulatePyModuleSelectOptions(S.ScriptNames, ActiveScriptSelect, NewScriptName);
                    });
                });
            });
        }
        else // Didn't select 'New Script'
        {
            PrevSelectedScriptIndex = ActiveScriptSelect.selectedIndex;
            const OldScriptName = ScriptEditingTA.getAttribute("name");
            if (OldScriptName !== null)
            {
                ProtexWindow.ProtexAPI.WriteScript((OldScriptName as string), ScriptEditingTA.value);
            }

            ProtexWindow.ProtexAPI.ReadScript(NewScriptName).then((Result: string) =>
            {
                ScriptEditingTA.setAttribute("name", NewScriptName);
                ScriptEditingTA.value = Result;
            });
        }
    };
    PopulatePyModuleSelectOptions(S.ScriptNames, ActiveScriptSelect, "");
    ToolbarContainer.appendChild(ActiveScriptSelect);

    const ExtractorSelect = document.createElement("select");
    ExtractorSelect.id = "extractor-select";
    let PrevSelectedExtractorIndex = -1;
    ExtractorSelect.onchange = async () =>
    {
        if ((PrevSelectedExtractorIndex !== -1) &&
            (PrevSelectedExtractorIndex !== ExtractorSelect.length - 1))
        {
            const ExtrToSave  = S.Extractors[PrevSelectedExtractorIndex];
            ExtrToSave.Categories = [];
            ExtrToSave.Patterns = []

            const PatternsContainer = TryGetElementByID("patterns-container");
            let Patterns: string[] = [];
            for (const Elem of PatternsContainer.getElementsByClassName("pattern-input"))
            {
                Patterns.push((Elem as HTMLInputElement).value);
            }
            ExtrToSave.Patterns = Patterns.slice(0);

            const CatItems = document.getElementsByClassName("cat-fields-item");
            let CatItemIndex = 0;
            for (const CatItem of CatItems)
            {
                const CatNames = document.getElementsByClassName("cat-name-input");
                if (CatItemIndex >= CatNames.length)
                {
                    break;
                }

                const Conditionses = document.getElementsByClassName("conditions-input");
                if (CatItemIndex >= Conditionses.length)
                {
                    break;
                }

                ExtrToSave.Categories.push({
                    Name: (CatNames[CatItemIndex] as HTMLInputElement).value,
                    Conditions: (Conditionses[CatItemIndex] as HTMLInputElement).value
                });

                CatItemIndex += 1
            }
        }

        // Remove old DOM elements

        const CategoryFieldItems = document.getElementsByClassName("cat-fields-item");
        for (const CatItem of CategoryFieldItems)
        {
            CatItem.remove();
        }
        for (const PatternEntry of PatternsContainer.getElementsByClassName("pattern-entry"))
        {
            PatternEntry.remove();
        }

        if (ExtractorSelect.value === "New Extractor")
        {
            await GetUserInput().then((Result) => {
                const NewExtractorName = Result;
                if (NewExtractorName === "")
                {
                    ExtractorSelect.selectedIndex = PrevSelectedExtractorIndex;

                    // NOTE(cjb): Because we are allways removing cat dom elements if you cancel
                    // adding an extractor restore it's dom elements.

                    for (const Cat of S.Extractors[ExtractorSelect.selectedIndex].Categories)
                    {
                        NewCatFields(S.ScriptNames, Cat.Name, Cat.Conditions);
                    }
                    for (const P of S.Extractors[ExtractorSelect.selectedIndex].Patterns)
                    {
                        AddPattern(P);
                    }
                    return;
                }

                const PatternsContainer = TryGetElementByID("patterns-container");
                let Patterns: string[] = [];
                for (const Elem of PatternsContainer.getElementsByClassName("pattern-input"))
                {
                    Patterns.push((Elem as HTMLInputElement).value);
                }
                AddExtr(S.Extractors, NewExtractorName, Patterns, []);
            });
        }
        else // Otherwise switch extractors
        {
            for (const Cat of S.Extractors[ExtractorSelect.selectedIndex].Categories)
            {
                NewCatFields(S.ScriptNames, Cat.Name, Cat.Conditions);
            }
            for (const P of S.Extractors[ExtractorSelect.selectedIndex].Patterns)
            {
                AddPattern(P);
            }
        }

        PrevSelectedExtractorIndex = ExtractorSelect.selectedIndex;
    }

    const AddExtractorOption = document.createElement("option");
    AddExtractorOption.text = "New Extractor";
    AddExtractorOption.value = "New Extractor";
    ExtractorSelect.add(AddExtractorOption);

    ExtractorSelect.selectedIndex = -1;
    ToolbarContainer.appendChild(ExtractorSelect);

    const ABBoxContainer = document.createElement("div");
    ABBoxContainer.id = "ab-box-container";
    AContainer.appendChild(ABBoxContainer);

    const ABox = document.createElement("div");
    ABox.className = "ab-item";
    ABBoxContainer.appendChild(ABox);

    const BBox = document.createElement("div");
    BBox.className = "ab-item";
    ABBoxContainer.appendChild(BBox);

    const PatternsContainer = document.createElement("div");
    PatternsContainer.id = "patterns-container";
    BBox.appendChild(PatternsContainer);

    const ScriptEditingTA = document.createElement("textarea");
    ScriptEditingTA.id = "script-editing-ta";
    ScriptEditingTA.onkeyup = (E: KeyboardEvent) =>
    {
        if (E.ctrlKey && E.key === "s")
        {
            const ScriptName = ScriptEditingTA.getAttribute("name");
            if (ScriptName !== null)
            {
                ProtexWindow.ProtexAPI.WriteScript((ScriptName as string), ScriptEditingTA.value);
            }
        }
    }
    ScriptEditingTA.setAttribute("spellcheck", "false");
    BBox.appendChild(ScriptEditingTA);

    const AddPatternButton = document.createElement("button");
    AddPatternButton.innerText = "+";
    AddPatternButton.className = "pattern-entry-button";
    AddPatternButton.onclick = () => AddPattern("");
    PatternsContainer.appendChild(AddPatternButton);

    // Document's text area
    const DEBUGText = "Prep Cooks/Cooks Starting at $25 an Hour Qualifications\n    Restaurant: 1 year (Required)\n    Work authorization (Required)\n    High school or equivalent (Preferred)\nBenefits\n\Pulled from the full job description\n\Employee discount\n\Paid time off\n\Full Job Description\nCooks\nGreat Opportunity to work at a new all-seasons resort in Northern Catskills - Wylder Windham Hotel.\nWe are looking for a dedicated, passionate, and skilled person to become a part of our pre-opening kitchen team for our Babbler's Restaurant. Our four-season resort will offer 110 hotel rooms, 1 restaurant, 1 Bakery with 20 acres of land alongside the Batavia Kill River, our family-friendly, all-season resort is filled with endless opportunities. This newly reimagined property offers banquet, wedding, and event facilities. We are looking for someone who is both willing to roll up their sleeves and work hard and has a desire to produce a first-class experience for our guests. Looking for applicants who are positive, upbeat, team-oriented, and a people person.\nWylder is an ever growing hotel brand with locations in Lake Tahoe, California and Tilghman Maryland.\nLots of room for upward growth within the company at the Wylder Windham property and Beyond.\nYoung at heart, active, ambitious individuals encouraged to apply!\nMust work weekends, nights, holidays and be flexible with schedule. Must be able to lift 50 pounds and work a physical Labor Job.\nWylder's culture & motto: \"Everyone does everything, no one is above doing anything and the words that's not my job don't exist here\". We are here to make the guest experience the best it can be. We all work as a team and help one another out from the front desk to the restaurant and housekeeping to maintenance. We are dog and family-friendly in all aspects!.\nWylder's culture & motto: \"Everyone does everything, no one is above doing anything and the words that's not my job don't exist here\". We are here to make the guest experience the best it can be. We all work as a team and help one another out from the front desk to the restaurant and housekeeping to maintenance. We are dog and family friendly in all aspects!\nCompetitive Pay- starting at $25-$26+ per hour based on experience\nJob Type: Full-time/Part-Time\nJob Type: Full-time\nPay: From $25-$26+ per hour based on experience\nBenefits:\n    Employee discount\n\    Paid time off\nSchedule:\n    10 hour shift\n\    8 hour shift\n\    Every weekend\n\    Holidays\n\    Monday to Friday\n\    Weekend availability\nEducation:\n    High school or equivalent (Preferred)\nExperience:\n    cooking: 1 year (Preferred)\nWork Location: One location\nJob Type: Full-time\nPay: $25.00 - $26.00 per hour\nBenefits:\n    Employee discount\n\    Paid time off\nPhysical setting:\n    Casual dining restaurant\nSchedule:\n    8 hour shift\n\    Day shift\n\    Holidays\n\    Monday to Friday\n\    Night shift\n\    Weekend availability\nEducation:\n    High school or equivalent (Preferred)\nExperience:\n    Restaurant: 1 year (Required)";
    const TA = document.createElement("textarea");
    TA.id = "text-area"; // NOTE(cjb): also working id...
    TA.value = DEBUGText;
    TA.style.display = "none";
    TA.addEventListener("blur", () => //TODO(cjb): fix me... <span> wrapping for multiple matches
    {
        TA.style.display = "none";
        PreText.style.display = "inline-block";

        const TextAreaText = TA.value;
        PreText.innerHTML = TextAreaText.slice(0, TA.selectionStart) +
                            `<span class="noice">` +
                            TextAreaText.slice(TA.selectionStart, TA.selectionEnd) +
                            `</span>` + TextAreaText.slice(TA.selectionEnd);

        // NOTE(cjb): There should allways be a last selected pattern input, unless
        // there are no inputs.
        const OptLSPI = LastSelectedPatternInput();
        if (OptLSPI == null)
            return;

        const LSPI = (OptLSPI as HTMLInputElement);
        LSPI.setAttribute("SO", `${TA.selectionStart}`);
        LSPI.setAttribute("EO", `${TA.selectionEnd}`);
        LSPI.value = Regexify(TextAreaText.slice(TA.selectionStart, TA.selectionEnd));
    });
    ABox.appendChild(TA);

    const PreText = document.createElement("pre");
    PreText.setAttribute("tabIndex", "0");
    PreText.id = "pre-text"; // working id name...
    PreText.innerHTML = DEBUGText;
    PreText.addEventListener("keydown", (E: Event) =>
    {
        if ((E as KeyboardEvent).key === "Enter")
        {
            // Toggle TA selection

            PreText.style.display = "none";
            TA.style.display = "inline-block";
            TA.focus();
        }
    });
    PreText.onclick = () =>
    {
        // Toggle TA selection

        PreText.style.display = "none";
        TA.style.display = "inline-block";
        TA.focus();
    }
    ABox.appendChild(PreText);

    const CategoryContainer = document.createElement("div");
    CategoryContainer.id = "category-container";
    AContainer.appendChild(CategoryContainer);

    CategoryContainer.onauxclick = (E: MouseEvent) =>
    {
        E.preventDefault();

        const RightClick = 2;
        if (E.button === RightClick)
        {
            if (S.Extractors.length > 0) // Have at least 1 extractor?
            {
                AddEmptyCat(S.ScriptNames, S.Extractors[ExtractorSelect.selectedIndex]);
            }
            else // TODO(cjb): Actually save categories and patterns to anon extractor def.
            {
                const FakeExtr: extr_def = {
                    Name: "fakiemcfake",
                    Patterns: [],
                    Categories: []
                };
                AddEmptyCat(S.ScriptNames, FakeExtr);
            }
        }
    }

    const SVGCategoryMask = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    SVGCategoryMask.id = "svg-category-mask";
    SVGCategoryMask.style.position = "absolute";
    SVGCategoryMask.setAttribute("width", `${CategoryContainer.clientWidth}`);
    SVGCategoryMask.setAttribute("height", `${CategoryContainer.clientHeight}`);
    window.onresize = () =>
    {
        SVGCategoryMask.setAttribute("width", `${CategoryContainer.clientWidth}`);
        SVGCategoryMask.setAttribute("height", `${CategoryContainer.clientHeight}`);
    }
    CategoryContainer.appendChild(SVGCategoryMask);

    const AutoCompleteMenu = document.createElement("menu");
    AutoCompleteMenu.id = "auto-complete-menu";
    AContainer.appendChild(AutoCompleteMenu);

    const DEBUGTextInfo = document.createElement("p");
    DEBUGTextInfo.className = "bottomleft";
    DEBUGTextInfo.id = "debug-text-info";
    document.addEventListener("keyup", (E: Event) => {
        if ((E as KeyboardEvent).key === "Tab")
        {
            if (E.target !== null)
            {
                const LocalName = (E.target as HTMLElement).localName;
                const ClassName = (E.target as HTMLElement).className;
                DEBUGTextInfo.innerText = `${LocalName}.${ClassName}`;
            }
        }
    });
    AContainer.appendChild(DEBUGTextInfo);

    // Ascii fox by Brian Kendig

    const AsciiFox4Motivation = document.createElement("pre");
    AsciiFox4Motivation.className = "bottomright";
    AsciiFox4Motivation.innerText = `
       |\\/|    ____
    .__.. \\   /\\  /
     \\_   /__/  \\/
     _/  __   __/
    /___/____/
    v0.5.0-alpha`;
    AContainer.appendChild(AsciiFox4Motivation);
}); // GetPyModule
