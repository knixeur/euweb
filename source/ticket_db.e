--****
-- == Ticket database helpers
--

namespace ticket_db

include std/datetime.e
include std/error.e
include std/get.e

include webclay/logging.e as log
include edbi/edbi.e

public constant MODULE_ID=1

public enum ID, CREATED_AT, SUBMITTED_BY_ID, ASSIGNED_TO_ID, SEVERITY_ID,
	CATEGORY_ID, STATUS_ID, STATE_ID, REPORTED_RELEASE, MILESTONE, SUBJECT, CONTENT,
	RESOLVED_AT, SVN_REV, SUBMITTED_BY, ASSIGNED_TO, SEVERITY, CATEGORY, STATUS,
	STATE, PRODUCT_ID, PRODUCT, TYPE_ID, TYPE

constant BASE_FROM = """
FROM
	ticket AS t
	join users AS tsb on tsb.id=t.submitted_by_id
	left join users AS tas on tas.id=t.assigned_to_id
	join ticket_severity AS tsev on tsev.id=t.severity_id
	join ticket_category AS tcat on tcat.id=t.category_id
	join ticket_status AS tstat on tstat.id=t.status_id
	join ticket_state AS tstate on tstate.id=t.state_id
	join ticket_product AS tprod on tprod.id=t.product_id
	join ticket_type AS ttype on ttype.id=t.type_id
WHERE
	t.id != 0
"""

constant BASE_QUERY = """SELECT
	t.id, t.created_at, t.submitted_by_id, t.assigned_to_id, t.severity_id,
	t.category_id, t.status_id, t.state_id, t.reported_release, t.milestone, t.subject,
    t.content, t.resolved_at, t.svn_rev, tsb.user AS submitted_by,
    tas.user AS assigned_to, tsev.name AS severity, tcat.name AS category,
    tstat.name AS status, tstate.name AS state, t.product_id, tprod.name, t.type_id,
    ttype.name
""" & BASE_FROM

--**
-- Get the number of tickets

public function count(sequence where = "")
    sequence sql = "SELECT COUNT(t.id) " & BASE_FROM
    if length(where) > 0 then
        sql &= " AND " & where
    end if

	return edbi:query_object(sql)
end function

--**
-- Get a list of tickets for the given criteria

public function get_list(integer offset=0, integer per_page=10, sequence where="")
	sequence sql = BASE_QUERY
	if length(where) then
		sql &= " AND " & where
	end if
	sql &= " ORDER BY tsev.position DESC, t.created_at"
	sql &= " LIMIT %d OFFSET %d"
	return edbi:query_rows(sql, { per_page, offset })
end function

--**
-- Get a single ticket

public function get(integer id)
	return edbi:query_row(BASE_QUERY & " AND t.id=%d", { id })
end function

--**
-- Insert a new ticket

public function create(integer type_id, integer product_id, integer severity_id,
		integer category_id, sequence reported_release, sequence milestone, sequence subject,
        sequence content)
	return edbi:execute("""INSERT INTO ticket (assigned_to_id, status_id, state_id, created_at,
		submitted_by_id, type_id, product_id, severity_id, category_id, reported_release, milestone,
        subject, content) VALUES (0, 1, 1, NOW(), %d, %d, %d, %d, %d, %s, %s, %s, %s)""", {
			current_user[USER_ID], type_id, product_id, severity_id,
			category_id, reported_release, milestone, subject, content }
		)
end function

--**
-- Update a ticket

public function update(integer id, integer type_id, integer severity_id,
		integer category_id, sequence reported_release, sequence milestone, integer assigned_to_id,
        integer status_id, integer state_id, sequence svn_rev)
	return edbi:execute("""UPDATE ticket SET type_id=%d, severity_id=%d,
		category_id=%d, reported_release=%s, milestone=%s, assigned_to_id=%d, status_id=%d, state_id=%d,
		svn_rev=%s WHERE id=%d""", { type_id, severity_id, category_id,
			reported_release, milestone, assigned_to_id, status_id, state_id, svn_rev, id })
end function
