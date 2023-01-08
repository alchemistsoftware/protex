function Init(): void
{
    const AContainer = document.getElementById("acontainer")
    if (AContainer == null)
    {
        throw "Couldn't get acontainer element";
    }

    const SampleText = "Prep Cooks/Cooks Starting at $25 an Hour Qualifications\n    Restaurant: 1 year (Required)\n    Work authorization (Required)\n    High school or equivalent (Preferred)\nBenefits\n\Pulled from the full job description\n\Employee discount\n\Paid time off\n\Full Job Description\nCooks\nGreat Opportunity to work at a new all-seasons resort in Northern Catskills - Wylder Windham Hotel.\nWe are looking for a dedicated, passionate, and skilled person to become a part of our pre-opening kitchen team for our Babbler's Restaurant. Our four-season resort will offer 110 hotel rooms, 1 restaurant, 1 Bakery with 20 acres of land alongside the Batavia Kill River, our family-friendly, all-season resort is filled with endless opportunities. This newly reimagined property offers banquet, wedding, and event facilities. We are looking for someone who is both willing to roll up their sleeves and work hard and has a desire to produce a first-class experience for our guests. Looking for applicants who are positive, upbeat, team-oriented, and a people person.\nWylder is an ever growing hotel brand with locations in Lake Tahoe, California and Tilghman Maryland.\nLots of room for upward growth within the company at the Wylder Windham property and Beyond.\nYoung at heart, active, ambitious individuals encouraged to apply!\nMust work weekends, nights, holidays and be flexible with schedule. Must be able to lift 50 pounds and work a physical Labor Job.\nWylder's culture & motto: \"Everyone does everything, no one is above doing anything and the words that's not my job don't exist here\". We are here to make the guest experience the best it can be. We all work as a team and help one another out from the front desk to the restaurant and housekeeping to maintenance. We are dog and family-friendly in all aspects!.\nWylder's culture & motto: \"Everyone does everything, no one is above doing anything and the words that's not my job don't exist here\". We are here to make the guest experience the best it can be. We all work as a team and help one another out from the front desk to the restaurant and housekeeping to maintenance. We are dog and family friendly in all aspects!\nCompetitive Pay- starting at $25-$26+ per hour based on experience\nJob Type: Full-time/Part-Time\nJob Type: Full-time\nPay: From $25-$26+ per hour based on experience\nBenefits:\n    Employee discount\n\    Paid time off\nSchedule:\n    10 hour shift\n\    8 hour shift\n\    Every weekend\n\    Holidays\n\    Monday to Friday\n\    Weekend availability\nEducation:\n    High school or equivalent (Preferred)\nExperience:\n    cooking: 1 year (Preferred)\nWork Location: One location\nJob Type: Full-time\nPay: $25.00 - $26.00 per hour\nBenefits:\n    Employee discount\n\    Paid time off\nPhysical setting:\n    Casual dining restaurant\nSchedule:\n    8 hour shift\n\    Day shift\n\    Holidays\n\    Monday to Friday\n\    Night shift\n\    Weekend availability\nEducation:\n    High school or equivalent (Preferred)\nExperience:\n    Restaurant: 1 year (Required)";
    const TA = document.createElement("textarea");
    TA.innerText = SampleText;
    AContainer.appendChild(TA);

    const ExtractorFieldsContainer = document.createElement("div");
    ExtractorFieldsContainer.id = "extractor-fields-container";
    AContainer.appendChild(ExtractorFieldsContainer);

    const ExtractorNameInput = document.createElement("input");
    ExtractorNameInput.name = "extractor_name";
    ExtractorFieldsContainer.appendChild(ExtractorNameInput);

    const ExtractorCountryInput = document.createElement("input");
    ExtractorCountryInput.name = "extractor_country";
    ExtractorCountryInput.maxLength = 2;
    ExtractorFieldsContainer.appendChild(ExtractorCountryInput);

    const ExtractorLanguageInput = document.createElement("input");
    ExtractorLanguageInput.name = "extractor_language";
    ExtractorLanguageInput.maxLength = 2;
    ExtractorFieldsContainer.appendChild(ExtractorLanguageInput);

    const AddExtractorButton = document.createElement("button");
    AddExtractorButton.innerText = "New extractor";
    ExtractorFieldsContainer.appendChild(AddExtractorButton);

    const AddCategoryButton = document.createElement("button");
    AddCategoryButton.innerText = "New category";
    AddCategoryButton.onclick = () =>
    {
        const CategoryFieldsContainer = document.getElementById("category-fields-container");
        if (CategoryFieldsContainer == null)
        {
            throw "Couldn't get div with id 'category-fields-container'";
        }

        const CategoryFieldsItem = document.createElement("div");
        CategoryFieldsItem.className = "category-fields-item";
        CategoryFieldsContainer.appendChild(CategoryFieldsItem);

        const CategoryNameInput = document.createElement("input");
        CategoryNameInput.name = "categroy_name";
        CategoryFieldsItem.appendChild(CategoryNameInput);

        const MainPyModuleInput = document.createElement("input");
        MainPyModuleInput.name = "main_py_module";
        CategoryFieldsItem.appendChild(MainPyModuleInput);
    };
    ExtractorFieldsContainer.appendChild(AddCategoryButton);

    const CategoryFieldsContainer = document.createElement("div");
    CategoryFieldsContainer.id = "category-fields-container";
    ExtractorFieldsContainer.appendChild(CategoryFieldsContainer);
}

/// Does various "setup-ee" things
function Setup(): void
{
}

Init();
