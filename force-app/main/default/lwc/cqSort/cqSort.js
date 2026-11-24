/**
 * cqSort: the sorting every CQ table uses. A table keeps one sort ({ key, dir }), draws its headings with heads(),
 * flips the sort on a heading click with nextSort(), and orders its rows with sortRows().
 * Markup (styles in cqStyles): th[scope=col][aria-sort] > button.cq-sortbtn[data-key] > label + span.cq-sortarrow(.asc|.desc)
 */
const blank = (x) => x === undefined || x === null || x === '';

/** Rows ordered by row[key]: numbers by value, text ignoring case (and reading 'Lot 9' before 'Lot 10'), blanks last. Ties keep their order. */
export function sortRows(rows, sort) {
    if (!sort || !sort.key) { return rows.slice(); }
    const m = sort.dir === 'desc' ? -1 : 1;
    return rows.map((r, i) => [r, i]).sort((x, y) => {
        const a = x[0][sort.key], b = y[0][sort.key];
        if (blank(a) || blank(b)) { return blank(a) && blank(b) ? x[1] - y[1] : blank(a) ? 1 : -1; }
        const c = typeof a === 'number' && typeof b === 'number' ? a - b
            : String(a).localeCompare(String(b), undefined, { numeric: true, sensitivity: 'base' });
        return c ? c * m : x[1] - y[1];
    }).map((x) => x[0]);
}

/** The sort after a click on a heading: a new column sorts ascending, the same column flips. */
export function nextSort(sort, key) {
    return sort && sort.key === key ? { key, dir: sort.dir === 'asc' ? 'desc' : 'asc' } : { key, dir: 'asc' };
}

/**
 * The headings for a template. cols: [{ key, label, num (right-aligned), cls, sortable (default true) }].
 * Each comes back with thCls, sortable, aria (aria-sort), arrowCls and title.
 */
export function heads(cols, sort) {
    return cols.map((c) => {
        const on = !!sort && sort.key === c.key;
        const sortable = c.sortable !== false;
        return { ...c, sortable, plain: !sortable,
            thCls: [c.num ? 'num' : '', c.cls || ''].join(' ').trim(),
            aria: !sortable ? undefined : on ? (sort.dir === 'desc' ? 'descending' : 'ascending') : 'none',
            arrowCls: 'cq-sortarrow' + (on ? ' ' + (sort.dir === 'desc' ? 'desc' : 'asc') : ''),
            title: 'Sort by ' + c.label };
    });
}
