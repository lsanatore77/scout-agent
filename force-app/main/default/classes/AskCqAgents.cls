/**
 * AskCqAgents
 * -----------
 * Finds an agent's Id by its API name, so a page can ask for "CQAI_Field_Action" rather than
 * carry an org-specific Id. The Id differs in every org; the API name does not.
 */
public with sharing class AskCqAgents {

    /** The agent's Id, or null when no agent with that API name exists in this org. */
    @AuraEnabled(cacheable=true)
    public static Id idFor(String developerName) {
        if (String.isBlank(developerName)) { return null; }
        // Dynamic: a saved class cannot name BotDefinition as a type, but a query can read it.
        List<SObject> bots = Database.query('SELECT Id FROM BotDefinition WHERE DeveloperName = :developerName LIMIT 1');
        return bots.isEmpty() ? null : bots[0].Id;
    }
}
