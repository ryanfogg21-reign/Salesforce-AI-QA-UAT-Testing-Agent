/**
 * ListTestScriptsActionTest
 * Tests for ListTestScriptsAction @InvocableMethod
 */
@IsTest
private class ListTestScriptsActionTest {

    @TestSetup
    static void setupData() {
        Test_Suite__c suite = new Test_Suite__c(
            Name      = 'Core Regression Suite',
            Active__c = true
        );
        insert suite;

        List<Test_Script__c> scripts = new List<Test_Script__c>{
            new Test_Script__c(
                Name          = 'Opportunity Creation - Regression',
                Status__c     = 'Active',
                Type__c       = 'Regression',
                Priority__c   = 'P1 - Critical',
                Tags__c       = 'opportunity, pipeline',
                Test_Suite__c = suite.Id
            ),
            new Test_Script__c(
                Name      = 'Lead Conversion - UAT',
                Status__c = 'Active',
                Type__c   = 'UAT',
                Tags__c   = 'lead, conversion'
            ),
            new Test_Script__c(
                Name      = 'Login Smoke Test',
                Status__c = 'Active',
                Type__c   = 'Smoke',
                Tags__c   = 'login, smoke'
            ),
            new Test_Script__c(
                Name      = 'Draft Script - Should Not Appear',
                Status__c = 'Draft',
                Type__c   = 'Functional'
            ),
            new Test_Script__c(
                Name      = 'Deprecated Script - Should Not Appear',
                Status__c = 'Deprecated',
                Type__c   = 'Regression'
            )
        };
        insert scripts;
    }

    // ─── Tests ────────────────────────────────────────────────────────────────

    @IsTest
    static void testListAll_ReturnsOnlyActive() {
        ListTestScriptsAction.ActionInput inp = new ListTestScriptsAction.ActionInput();
        // No filters — should return all 3 Active scripts

        Test.startTest();
        List<ListTestScriptsAction.ActionOutput> results =
            ListTestScriptsAction.listScripts(new List<ListTestScriptsAction.ActionInput>{ inp });
        Test.stopTest();

        Assert.areEqual(3, results[0].totalCount, 'Should return only Active scripts');
        Assert.isFalse(results[0].scriptNames.contains('Draft'), 'Draft scripts should be excluded');
        Assert.isFalse(results[0].scriptNames.contains('Deprecated'), 'Deprecated scripts should be excluded');
    }

    @IsTest
    static void testFilterByType_Regression() {
        ListTestScriptsAction.ActionInput inp = new ListTestScriptsAction.ActionInput();
        inp.typeFilter = 'Regression';

        Test.startTest();
        List<ListTestScriptsAction.ActionOutput> results =
            ListTestScriptsAction.listScripts(new List<ListTestScriptsAction.ActionInput>{ inp });
        Test.stopTest();

        Assert.areEqual(1, results[0].totalCount, 'Should return only Regression scripts');
        Assert.isTrue(results[0].scriptNames.contains('Opportunity Creation'));
    }

    @IsTest
    static void testFilterByType_UAT() {
        ListTestScriptsAction.ActionInput inp = new ListTestScriptsAction.ActionInput();
        inp.typeFilter = 'UAT';

        Test.startTest();
        List<ListTestScriptsAction.ActionOutput> results =
            ListTestScriptsAction.listScripts(new List<ListTestScriptsAction.ActionInput>{ inp });
        Test.stopTest();

        Assert.areEqual(1, results[0].totalCount);
        Assert.isTrue(results[0].scriptNames.contains('Lead Conversion'));
    }

    @IsTest
    static void testFilterByTag_Partial() {
        ListTestScriptsAction.ActionInput inp = new ListTestScriptsAction.ActionInput();
        inp.tagFilter = 'opportunity';

        Test.startTest();
        List<ListTestScriptsAction.ActionOutput> results =
            ListTestScriptsAction.listScripts(new List<ListTestScriptsAction.ActionInput>{ inp });
        Test.stopTest();

        Assert.areEqual(1, results[0].totalCount, 'Tag filter should partial-match');
        Assert.isTrue(results[0].scriptNames.contains('Opportunity'));
    }

    @IsTest
    static void testFilterBySuiteName() {
        ListTestScriptsAction.ActionInput inp = new ListTestScriptsAction.ActionInput();
        inp.suiteName = 'Core Regression Suite';

        Test.startTest();
        List<ListTestScriptsAction.ActionOutput> results =
            ListTestScriptsAction.listScripts(new List<ListTestScriptsAction.ActionInput>{ inp });
        Test.stopTest();

        Assert.areEqual(1, results[0].totalCount, 'Should return only scripts in that suite');
        Assert.isTrue(results[0].scriptNames.contains('Opportunity Creation'));
    }

    @IsTest
    static void testNoResults_ReturnsZeroCount() {
        ListTestScriptsAction.ActionInput inp = new ListTestScriptsAction.ActionInput();
        inp.typeFilter = 'End-to-End'; // no scripts of this type

        Test.startTest();
        List<ListTestScriptsAction.ActionOutput> results =
            ListTestScriptsAction.listScripts(new List<ListTestScriptsAction.ActionInput>{ inp });
        Test.stopTest();

        Assert.areEqual(0, results[0].totalCount);
        Assert.isTrue(results[0].statusMessage.containsIgnoreCase('No active'));
    }

    @IsTest
    static void testMaxResults_IsCapped() {
        // Insert 25 more scripts to test the cap
        List<Test_Script__c> extras = new List<Test_Script__c>();
        for (Integer i = 0; i < 25; i++) {
            extras.add(new Test_Script__c(
                Name      = 'Bulk Script ' + i,
                Status__c = 'Active',
                Type__c   = 'Functional'
            ));
        }
        insert extras;

        ListTestScriptsAction.ActionInput inp = new ListTestScriptsAction.ActionInput();
        inp.maxResults = 5;

        Test.startTest();
        List<ListTestScriptsAction.ActionOutput> results =
            ListTestScriptsAction.listScripts(new List<ListTestScriptsAction.ActionInput>{ inp });
        Test.stopTest();

        Assert.isTrue(results[0].totalCount <= 5, 'Should respect maxResults cap');
    }

    @IsTest
    static void testOutputContainsBulletPoints() {
        ListTestScriptsAction.ActionInput inp = new ListTestScriptsAction.ActionInput();

        Test.startTest();
        List<ListTestScriptsAction.ActionOutput> results =
            ListTestScriptsAction.listScripts(new List<ListTestScriptsAction.ActionInput>{ inp });
        Test.stopTest();

        Assert.isTrue(results[0].scriptListSummary.contains('•'),
            'Summary should use bullet points for agent readability');
    }
}
