/**
 * GetTestRunStatusAction
 *
 * Agentforce Agent Action — returns the current status and summary of a Test Run.
 * The agent calls this to check whether a run has completed and what the outcome was.
 */
public with sharing class GetTestRunStatusAction {

    // ─── Input ────────────────────────────────────────────────────────────────

    public class ActionInput {
        @InvocableVariable(
            label='Test Run ID'
            description='Salesforce record ID of the Test Run to check (e.g. a0Bxx000000xxxxx)'
            required=false
        )
        public String testRunId;

        @InvocableVariable(
            label='Test Run Name'
            description='Auto-number name of the Test Run (e.g. RUN-00001). Use this OR Test Run ID.'
            required=false
        )
        public String testRunName;
    }

    // ─── Output ───────────────────────────────────────────────────────────────

    public class ActionOutput {
        @InvocableVariable(label='Status')
        public String status;

        @InvocableVariable(label='Test Script Name')
        public String testScriptName;

        @InvocableVariable(label='Steps Passed')
        public Integer stepsPassed;

        @InvocableVariable(label='Steps Failed')
        public Integer stepsFailed;

        @InvocableVariable(label='Steps Total')
        public Integer stepsTotal;

        @InvocableVariable(label='Duration Seconds')
        public Integer durationSeconds;

        @InvocableVariable(label='Summary')
        public String summary;

        @InvocableVariable(label='Error Message')
        public String errorMessage;

        @InvocableVariable(label='Is Complete')
        public Boolean isComplete;

        @InvocableVariable(label='Status Message')
        public String statusMessage;
    }

    // ─── Invocable Method ─────────────────────────────────────────────────────

    @InvocableMethod(
        label='Get Test Run Status'
        description='Returns the current status, step counts, and summary for a Test Run record. Use after triggering a run to monitor progress.'
        category='QA Automation'
    )
    public static List<ActionOutput> getStatus(List<ActionInput> inputs) {
        List<ActionOutput> outputs = new List<ActionOutput>();

        for (ActionInput inp : inputs) {
            ActionOutput out = new ActionOutput();

            try {
                String whereClause = '';
                List<Test_Run__c> runs;

                if (String.isNotBlank(inp.testRunId)) {
                    runs = [
                        SELECT Id, Name, Status__c, Summary__c, Error_Message__c,
                               Steps_Passed__c, Steps_Failed__c, Steps_Total__c,
                               Start_Time__c, End_Time__c, Duration_Seconds__c,
                               Test_Script__r.Name
                        FROM Test_Run__c
                        WHERE Id = :inp.testRunId
                        LIMIT 1
                    ];
                } else if (String.isNotBlank(inp.testRunName)) {
                    runs = [
                        SELECT Id, Name, Status__c, Summary__c, Error_Message__c,
                               Steps_Passed__c, Steps_Failed__c, Steps_Total__c,
                               Start_Time__c, End_Time__c, Duration_Seconds__c,
                               Test_Script__r.Name
                        FROM Test_Run__c
                        WHERE Name = :inp.testRunName
                        LIMIT 1
                    ];
                } else {
                    out.statusMessage = 'Please provide either a Test Run ID or Test Run Name.';
                    out.isComplete = false;
                    outputs.add(out);
                    continue;
                }

                if (runs.isEmpty()) {
                    out.statusMessage = 'No Test Run found with the provided ID or name.';
                    out.isComplete = false;
                    outputs.add(out);
                    continue;
                }

                Test_Run__c run = runs[0];
                Set<String> terminalStatuses = new Set<String>{'Passed', 'Failed', 'Error', 'Cancelled'};

                out.status         = run.Status__c;
                out.testScriptName = run.Test_Script__r.Name;
                out.stepsPassed    = run.Steps_Passed__c != null ? Integer.valueOf(run.Steps_Passed__c) : 0;
                out.stepsFailed    = run.Steps_Failed__c != null ? Integer.valueOf(run.Steps_Failed__c) : 0;
                out.stepsTotal     = run.Steps_Total__c  != null ? Integer.valueOf(run.Steps_Total__c)  : 0;
                out.durationSeconds = run.Duration_Seconds__c != null ? Integer.valueOf(run.Duration_Seconds__c) : null;
                out.summary        = run.Summary__c;
                out.errorMessage   = run.Error_Message__c;
                out.isComplete     = terminalStatuses.contains(run.Status__c);

                // Build a human-readable status message for the agent to relay
                if (out.isComplete) {
                    out.statusMessage = 'Test Run ' + run.Name + ' for script "' + run.Test_Script__r.Name
                        + '" has completed with status: ' + run.Status__c + '. '
                        + out.stepsPassed + ' of ' + out.stepsTotal + ' steps passed'
                        + (out.stepsFailed > 0 ? ', ' + out.stepsFailed + ' failed.' : '.')
                        + (String.isNotBlank(run.Summary__c) ? ' Summary: ' + run.Summary__c : '');
                } else {
                    out.statusMessage = 'Test Run ' + run.Name + ' is currently ' + run.Status__c
                        + '. Steps completed so far: ' + (out.stepsPassed + out.stepsFailed)
                        + ' of ' + out.stepsTotal + '.';
                }

            } catch (Exception e) {
                out.isComplete = false;
                out.statusMessage = 'Error retrieving run status: ' + e.getMessage();
            }

            outputs.add(out);
        }

        return outputs;
    }
}
