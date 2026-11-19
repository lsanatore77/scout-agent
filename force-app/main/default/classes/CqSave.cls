/**
 * What to tell the person when a save is refused. Saves run in user mode, so a person without access to an
 * object gets a SecurityException (a field they cannot edit gets a DmlException, which each save already explains).
 */
public with sharing class CqSave {
    public static final String DENIED = 'you do not have permission to do this. Ask your administrator for access.';
    /** The reason in plain words, for after "It was not saved: ". */
    public static String why(Exception e) {
        if (e instanceof DmlException) { return ((DmlException) e).getDmlMessage(0); }
        if (e instanceof SecurityException) { return DENIED; }
        return e.getMessage();
    }
}
