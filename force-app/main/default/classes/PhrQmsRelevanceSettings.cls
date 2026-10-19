/**
 * PhrQmsRelevanceSettings
 * -----------------------
 * One place for the relevance model switch and every placeholder weight.
 * All numbers are placeholders to fine-tune later.
 *
 * To go back to the original ranking without touching anything else, set
 * useNewModel to false and redeploy this one small class. PhrQmsPanelController
 * still contains the original finders and ranking and uses them when the
 * switch is off.
 */
public with sharing class PhrQmsRelevanceSettings {

    /** true = relevance model (colour, score, tiers, set-aside); false = original ranking. */
    @TestVisible public static Boolean useNewModel = true;

    // Product link points
    public static final Integer PTS_LINK_OWN = 35;
    public static final Integer PTS_LINK_COMPONENT = 25;
    public static final Integer PTS_LINK_OTHER = 15;
    // Symptom points (0 to this value)
    public static final Integer PTS_SYMPTOM_MAX = 35;
    public static final Integer PTS_SYMPTOM_CODE = 30;
    public static final Integer PTS_SYMPTOM_FAILED_INSPECTION = 25;
    public static final Integer PTS_SYMPTOM_CHANGE_BEFORE = 20;
    // Current points
    public static final Integer PTS_CURRENT_BOTH = 15;
    public static final Integer PTS_CURRENT_ONE = 8;
    // Bonuses
    public static final Integer PTS_LOT = 15;
    public static final Integer PTS_PART_DESIGN_CHANGE = 15;
    public static final Integer PTS_CHANGE_BEFORE_COMPLAINT = 10;

    /** Text similarity (Dice) at which the symptom criterion is met, and at which it earns full points. */
    public static final Double SYMPTOM_THRESHOLD = 0.25;
    public static final Double SYMPTOM_FULL = 0.60;

    /** Change order product-link weight by class. */
    public static final Double DOCUMENT_ONLY_LINK_FACTOR = 0.0;
    public static final Double UNCLASSIFIED_LINK_FACTOR = 0.5;

    public static final Integer TOP_LEADS = 5;
    public static final Integer OTHER_PRODUCT_CAP = 10;
    public static final Integer NEW_WINDOW_DAYS = 30;
    public static final Integer CHANGE_WINDOW_DAYS = 180;
    public static final Integer MAX_ROWS = 200;
}
