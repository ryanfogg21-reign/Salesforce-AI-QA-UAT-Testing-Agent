/**
 * CreateSampleTestData.apex
 *
 * Anonymous Apex script — creates a full sample Test Suite, Test Script,
 * and Test Steps for the QA Test Agent demo.
 *
 * Run via:
 *   sf apex run --file scripts/apex/CreateSampleTestData.apex -o AgentforceDevOrg
 *
 * Idempotent: skips creation if records with these names already exist.
 */

// ─── 1. Test Suite ────────────────────────────────────────────────────────────

Test_Suite__c suite;
List<Test_Suite__c> existingSuites = [
    SELECT Id FROM Test_Suite__c WHERE Name = 'Core CRM Regression Suite' LIMIT 1
];
if (existingSuites.isEmpty()) {
    suite = new Test_Suite__c(
        Name                         = 'Core CRM Regression Suite',
        Active__c                    = true,
        Description__c               = 'Regression suite covering the core Salesforce CRM flows: '
                                     + 'Opportunity creation, Lead conversion, and Account management. '
                                     + 'Run after every release to verify key business processes.',
        Target_Org_URL__c            = 'https://agentforce-dev-ed.develop.my.salesforce.com',
        Named_Credential_API_Name__c = 'Browser_Agent_Service',
        Last_Run_Status__c           = 'Not Run'
    );
    insert suite;
    System.debug('✅ Created Test Suite: ' + suite.Id);
} else {
    suite = existingSuites[0];
    System.debug('ℹ️  Test Suite already exists: ' + suite.Id);
}

// ─── 2. Test Script ───────────────────────────────────────────────────────────

Test_Script__c script;
List<Test_Script__c> existingScripts = [
    SELECT Id FROM Test_Script__c WHERE Name = 'Create New Opportunity - Full Flow' LIMIT 1
];
if (existingScripts.isEmpty()) {
    script = new Test_Script__c(
        Name                   = 'Create New Opportunity - Full Flow',
        Test_Suite__c          = suite.Id,
        Status__c              = 'Active',
        Type__c                = 'Regression',
        Priority__c            = 'P1 - Critical',
        Description__c         = 'Validates the full Opportunity creation flow from the Opportunities '
                               + 'list view through to a saved record with all required fields populated. '
                               + 'Covers: navigation, form entry, picklist selection, date entry, and save. '
                               + 'The AI agent should interact with the UI exactly as a user would, '
                               + 'including waiting for Lightning spinners to complete.',
        Continue_On_Failure__c = false,
        Timeout_Minutes__c     = 10,
        Tags__c                = 'opportunity, pipeline, regression, core-crm',
        Last_Run_Status__c     = 'Not Run',
        Notes__c               = 'This is the most critical regression test. Run first in every suite execution. '
                               + 'Ensure the test user has Create permission on Opportunity.'
    );
    insert script;
    System.debug('✅ Created Test Script: ' + script.Id);
} else {
    script = existingScripts[0];
    System.debug('ℹ️  Test Script already exists: ' + script.Id);
}

// ─── 3. Test Steps ────────────────────────────────────────────────────────────

Integer existingStepCount = [
    SELECT COUNT() FROM Test_Step__c WHERE Test_Script__c = :script.Id
];

if (existingStepCount == 0) {
    List<Test_Step__c> steps = new List<Test_Step__c>{

        new Test_Step__c(
            Test_Script__c      = script.Id,
            Step_Number__c      = 10,
            Step_Type__c        = 'Navigate',
            Description__c      = 'Navigate to the Opportunities tab in Salesforce Lightning.',
            Expected_Outcome__c = 'The Opportunities list view is displayed with the standard list view '
                                + 'columns visible and a "New" button in the top right corner.',
            Active__c           = true,
            Timeout_Seconds__c  = 15,
            Max_Actions__c      = 5
        ),

        new Test_Step__c(
            Test_Script__c      = script.Id,
            Step_Number__c      = 20,
            Step_Type__c        = 'Click',
            Description__c      = 'Click the "New" button to open the New Opportunity form.',
            Expected_Outcome__c = 'The New Opportunity quick action modal or full form page opens. '
                                + 'The form should show fields including Opportunity Name, Account Name, '
                                + 'Close Date, and Stage.',
            Active__c           = true,
            Timeout_Seconds__c  = 20,
            Max_Actions__c      = 5
        ),

        new Test_Step__c(
            Test_Script__c      = script.Id,
            Step_Number__c      = 30,
            Step_Type__c        = 'Fill',
            Description__c      = 'Fill in the Opportunity Name field with the value "QA Test Opportunity - '
                                + String.valueOf(Date.today()) + '".',
            Expected_Outcome__c = 'The Opportunity Name field contains the text "QA Test Opportunity" '
                                + 'and the field border is no longer highlighted red (no validation error).',
            Active__c           = true,
            Timeout_Seconds__c  = 15,
            Max_Actions__c      = 8
        ),

        new Test_Step__c(
            Test_Script__c      = script.Id,
            Step_Number__c      = 40,
            Step_Type__c        = 'Fill',
            Description__c      = 'Set the Close Date field to a date 30 days from today.',
            Expected_Outcome__c = 'The Close Date field is populated with a valid future date '
                                + 'and shows no validation error.',
            Active__c           = true,
            Timeout_Seconds__c  = 15,
            Max_Actions__c      = 8
        ),

        new Test_Step__c(
            Test_Script__c      = script.Id,
            Step_Number__c      = 50,
            Step_Type__c        = 'Fill',
            Description__c      = 'Select "Prospecting" from the Stage picklist.',
            Expected_Outcome__c = 'The Stage field shows "Prospecting" as the selected value. '
                                + 'The Probability field may auto-populate to 10%.',
            Active__c           = true,
            Timeout_Seconds__c  = 15,
            Max_Actions__c      = 8
        ),

        new Test_Step__c(
            Test_Script__c      = script.Id,
            Step_Number__c      = 60,
            Step_Type__c        = 'Click',
            Description__c      = 'Click the "Save" button to save the new Opportunity record.',
            Expected_Outcome__c = 'The Opportunity record is saved successfully. The page navigates '
                                + 'to the Opportunity detail page showing the record name "QA Test Opportunity" '
                                + 'in the header. No error toast or error messages are displayed.',
            Active__c           = true,
            Timeout_Seconds__c  = 30,
            Max_Actions__c      = 8
        ),

        new Test_Step__c(
            Test_Script__c      = script.Id,
            Step_Number__c      = 70,
            Step_Type__c        = 'Assert',
            Description__c      = 'Verify that the saved Opportunity record detail page shows '
                                + 'the correct Stage value of "Prospecting" and a Close Date is visible.',
            Expected_Outcome__c = 'The Opportunity detail page is displayed. The Stage field shows '
                                + '"Prospecting". The Close Date field shows a valid date. '
                                + 'No error banners or warning messages are shown on the page.',
            Active__c           = true,
            Timeout_Seconds__c  = 15,
            Max_Actions__c      = 5
        ),

        new Test_Step__c(
            Test_Script__c      = script.Id,
            Step_Number__c      = 80,
            Step_Type__c        = 'Screenshot',
            Description__c      = 'Take a screenshot of the saved Opportunity record detail page '
                                + 'as evidence of successful test completion.',
            Expected_Outcome__c = 'A screenshot is captured showing the full Opportunity detail page '
                                + 'with the record name, Stage, Close Date, and no error messages visible.',
            Active__c           = true,
            Timeout_Seconds__c  = 10,
            Max_Actions__c      = 3
        )
    };

    insert steps;
    System.debug('✅ Created ' + steps.size() + ' Test Steps');

    // Update Total_Steps count on the script
    update new Test_Script__c(
        Id           = script.Id,
        Total_Steps__c = steps.size()
    );

} else {
    System.debug('ℹ️  Test Steps already exist (' + existingStepCount + ' steps)');
}

// ─── Summary ──────────────────────────────────────────────────────────────────

System.debug('');
System.debug('══════════════════════════════════════════════');
System.debug('  Sample QA Test Data Created Successfully');
System.debug('══════════════════════════════════════════════');
System.debug('  Suite:  Core CRM Regression Suite');
System.debug('  Script: Create New Opportunity - Full Flow');
System.debug('  Steps:  8 (Navigate → Click → Fill × 3 → Click → Assert → Screenshot)');
System.debug('');
System.debug('  To test the agent, say:');
System.debug('  "Run the Create New Opportunity - Full Flow test"');
System.debug('══════════════════════════════════════════════');
