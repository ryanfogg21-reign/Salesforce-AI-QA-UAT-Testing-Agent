/**
 * ListTestScriptsAction
 *
 * Agentforce Agent Action — returns a list of available Active test scripts,
 * optionally filtered by Type or Tag. The agent calls this when a user asks
 * "what tests are available?" or "run all regression tests".
 */
public with sharing class ListTestScriptsAction {

    // ─── Input ────────────────────────────────────────────────────────────────

    public class ActionInput {
        @InvocableVariable(
            label='Filter by Type'
            description='Optional. Filter scripts by Type picklist value: UAT, Regression, Smoke, Functional, Integration, End-to-End'
            required=false
        )
        public String typeFilter;

        @InvocableVariable(
            label='Filter by Tag'
            description='Optional. Returns scripts whose Tags field contains this value (partial match)'
            required=false
        )
        public String tagFilter;

        @InvocableVariable(
            label='Filter by Suite Name'
            description='Optional. Returns only scripts belonging to the named Test Suite'
            required=false
        )
        public String suiteName;

        @InvocableVariable(
            label='Max Results'
            description='Maximum number of scripts to return. Defaults to 20.'
            required=false
        )
        public Integer maxResults;
    }

    // ─── Output ───────────────────────────────────────────────────────────────

    public class ActionOutput {
        @InvocableVariable(label='Script List Summary')
        public String scriptListSummary;

        @InvocableVariable(label='Script Names (comma-separated)')
        public String scriptNames;

        @InvocableVariable(label='Total Count')
        public Integer totalCount;

        @InvocableVariable(label='Status Message')
        public String statusMessage;
    }

    // ─── Invocable Method ─────────────────────────────────────────────────────

    @InvocableMethod(
        label='List Available Test Scripts'
        description='Returns a list of active Test Scripts, optionally filtered by type, tag, or suite. Use this to discover what tests exist before running them.'
        category='QA Automation'
    )
    public static List<ActionOutput> listScripts(List<ActionInput> inputs) {
        List<ActionOutput> outputs = new List<ActionOutput>();

        for (ActionInput inp : inputs) {
            ActionOutput out = new ActionOutput();

            try {
                Integer maxRows = (inp.maxResults != null && inp.maxResults > 0)
                    ? Math.min(inp.maxResults, 50)
                    : 20;

                // Build dynamic SOQL
                String query = 'SELECT Id, Name, Type__c, Priority__c, Last_Run_Status__c, '
                             + 'Tags__c, Test_Suite__r.Name, Total_Steps__c, Pass_Rate__c '
                             + 'FROM Test_Script__c WHERE Status__c = \'Active\'';

                if (String.isNotBlank(inp.typeFilter)) {
                    query += ' AND Type__c = \'' + String.escapeSingleQuotes(inp.typeFilter) + '\'';
                }
                if (String.isNotBlank(inp.tagFilter)) {
                    query += ' AND Tags__c LIKE \'%' + String.escapeSingleQuotes(inp.tagFilter) + '%\'';
                }
                if (String.isNotBlank(inp.suiteName)) {
                    query += ' AND Test_Suite__r.Name = \'' + String.escapeSingleQuotes(inp.suiteName) + '\'';
                }

                query += ' ORDER BY Priority__c ASC NULLS LAST, Name ASC LIMIT ' + maxRows;

                List<Test_Script__c> scripts = Database.query(query);

                if (scripts.isEmpty()) {
                    out.totalCount = 0;
                    out.statusMessage = 'No active test scripts found'
                        + (String.isNotBlank(inp.typeFilter) ? ' of type ' + inp.typeFilter : '')
                        + (String.isNotBlank(inp.tagFilter)  ? ' with tag "' + inp.tagFilter + '"' : '')
                        + '.';
                    outputs.add(out);
                    continue;
                }

                // Build a readable list for the agent to summarize
                List<String> names = new List<String>();
                List<String> lines = new List<String>();
                for (Test_Script__c s : scripts) {
                    names.add(s.Name);
                    String line = '• ' + s.Name
                        + ' [' + s.Type__c + ']'
                        + (s.Total_Steps__c != null ? ' — ' + Integer.valueOf(s.Total_Steps__c) + ' steps' : '')
                        + (String.isNotBlank(s.Last_Run_Status__c) && s.Last_Run_Status__c != 'Not Run'
                            ? ' — Last: ' + s.Last_Run_Status__c : '');
                    lines.add(line);
                }

                out.totalCount       = scripts.size();
                out.scriptNames      = String.join(names, ', ');
                out.scriptListSummary = String.join(lines, '\n');
                out.statusMessage    = 'Found ' + scripts.size() + ' active test script(s):\n'
                    + out.scriptListSummary;

            } catch (Exception e) {
                out.statusMessage = 'Error listing test scripts: ' + e.getMessage();
            }

            outputs.add(out);
        }

        return outputs;
    }
}
