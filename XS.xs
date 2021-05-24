#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#include <string.h>

#include "toml.h"
#include "tomlxs.h"

#define DOCUMENT_CLASS "TOML::XS::Document"
#define TIMESTAMP_CLASS "TOML::XS::Timestamp"
#define BOOLEAN_CLASS "TOML::XS"

#define CROAK_ERR_MSG_FN "TOML::XS::_croak_err_message_from_pieces"

#define PERL_TRUE get_sv(BOOLEAN_CLASS "::true", 0)
#define PERL_FALSE get_sv(BOOLEAN_CLASS "::false", 0)

#define UNUSED(x) (void)(x)

#ifdef PL_phase
#define _IS_GLOBAL_DESTRUCT (PL_phase == PERL_PHASE_DESTRUCT)
#else
#define _IS_GLOBAL_DESTRUCT PL_dirty
#endif

#define ERR_PATH_UNSHIFT(err_path_ptr, sv) STMT_START {   \
    if (NULL == *err_path_ptr) *err_path_ptr = newAV(); \
    av_unshift(*err_path_ptr, 1); \
    av_store(*err_path_ptr, 0, sv); \
} STMT_END

#define _datum_timestamp_to_sv(datum) _ptr_to_svrv(aTHX_ datum.u.ts, gv_stashpv(TIMESTAMP_CLASS, FALSE))

#define _verify_no_null(tomlstr, tomllen)               \
    if (strchr(tomlstr, 0) != (tomlstr + tomllen)) {    \
        croak(                                          \
            "String contains a NUL at index %" UVf "!", \
            (UV)(strchr(tomlstr, 0) - tomlstr)          \
        );                                              \
    }

#define _verify_valid_utf8(tomlstr, tomllen)                    \
    if (!is_utf8_string( (const U8*)tomlstr, tomllen )) {       \
        U8* ep;                                                 \
        const U8** epptr = (const U8**) &ep;                    \
        is_utf8_string_loc((const U8*)tomlstr, tomllen, epptr); \
        croak(                                                  \
            "String contains non-UTF-8 at index %" UVf "!",     \
            (UV)((char*) ep - tomlstr)                          \
        );                                                      \
    }

static inline SV* _datum_string_to_sv( pTHX_ toml_datum_t d ) {
#if TOMLXS_SV_CAN_USE_EXTERNAL_STRING
    /* More efficient: make the SV use the existing string.
       (Would sv_usepvn() work just as well??)
    */
    SV* ret = newSV(0);
    SvUPGRADE(ret, SVt_PV);
    SvPV_set(ret, d.u.s);
    SvPOK_on(ret);
    SvCUR_set(ret, strlen(d.u.s));
    SvLEN_set(ret, SvCUR(ret));
    SvUTF8_on(ret);
#else
    /* Slow but safe: copy the string into the PV. */
    SV* ret = newSVpvn_utf8(d.u.s, strlen(d.u.s), TRUE);
    tomlxs_free_string(d.u.s);
#endif

    return ret;
}

#define _datum_boolean_to_sv(d) \
    SvREFCNT_inc(d.u.b ? PERL_TRUE : PERL_FALSE);

#define _datum_integer_to_sv(d) \
    newSViv((IV)d.u.i);

#define _datum_double_to_sv(datum) \
    newSVnv((NV)datum.u.d);

#define RETURN_IF_DATUM_IS_STRING(d) \
    if (d.ok) return _datum_string_to_sv(aTHX_ d);

#define RETURN_IF_DATUM_IS_BOOLEAN(d) \
    if (d.ok) return _datum_boolean_to_sv(d);

#define RETURN_IF_DATUM_IS_INTEGER(d)   \
    if (d.ok) return _datum_integer_to_sv(d);

#define RETURN_IF_DATUM_IS_DOUBLE(d)    \
    if (d.ok) return _datum_double_to_sv(d);

#define RETURN_IF_DATUM_IS_TIMESTAMP(d) \
    if (d.ok) return _datum_timestamp_to_sv(d);

/* ---------------------------------------------------------------------- */

SV* _ptr_to_svrv(pTHX_ void* ptr, HV* stash) {
    SV* referent = newSVuv( PTR2UV(ptr) );
    SV* retval = newRV_noinc(referent);
    sv_bless(retval, stash);

    return retval;
}

toml_table_t* _get_toml_table_from_sv(pTHX_ SV *self_sv) {
    SV *referent = SvRV(self_sv);
    return INT2PTR(toml_table_t*, SvUV(referent));
}

toml_timestamp_t* _get_toml_timestamp_from_sv(pTHX_ SV *self_sv) {
    SV *referent = SvRV(self_sv);
    return INT2PTR(toml_timestamp_t*, SvUV(referent));
}

SV* _toml_table_value_to_sv(pTHX_ toml_table_t* curtab, const char* key, AV** err_path_ptr);
SV* _toml_array_value_to_sv(pTHX_ toml_array_t* arr, int i, AV** err_path_ptr);

SV* _toml_table_to_sv(pTHX_ toml_table_t* tab, AV** err_path_ptr) {
    int i;

    /* Doesn’t need to be mortal since this should not throw.
        Should that ever change this will need to be mortal then
        de-mortalized.
    */
    HV* hv = newHV();

    for (i = 0; ; i++) {
        const char* key = toml_key_in(tab, i);
        if (!key) break;

        SV* sv = _toml_table_value_to_sv(aTHX_ tab, key, err_path_ptr);

        if (NULL == sv) {
            SvREFCNT_dec((SV*)hv);
            SV* piece = newSVpv(key, 0);
            sv_utf8_decode(piece);
            ERR_PATH_UNSHIFT(err_path_ptr, piece);
            return NULL;
        }

        hv_store(hv, key, strlen(key), sv, 0);
    }

    return newRV_noinc( (SV *) hv );
}

SV* _toml_array_to_sv(pTHX_ toml_array_t* arr, AV** err_path_ptr) {
    int i;

    /* Doesn’t need to be mortal since this should not throw.
        Should that ever change this will need to be mortal then
        de-mortalized.
    */
    AV* av = newAV();

    int size = toml_array_nelem(arr);

    av_extend(av, size - 1);

    for (i = 0; i<size; i++) {
        SV* sv = _toml_array_value_to_sv(aTHX_ arr, i, err_path_ptr);

        if (NULL == sv) {
            SvREFCNT_dec((SV*)av);
            ERR_PATH_UNSHIFT(err_path_ptr, newSViv(i));
            return NULL;
        }

        av_store(av, i, sv);
    }

    return newRV_noinc( (SV *) av );
}

SV* _toml_table_value_to_sv(pTHX_ toml_table_t* curtab, const char* key, AV** err_path_ptr) {
    toml_array_t* arr;
    toml_table_t* tab;

    if (0 != (arr = toml_array_in(curtab, key))) {
        return _toml_array_to_sv(aTHX_ arr, err_path_ptr);
    }

    if (0 != (tab = toml_table_in(curtab, key))) {
        return _toml_table_to_sv(aTHX_ tab, err_path_ptr);
    }

    toml_datum_t d;

    d = toml_string_in(curtab, key);
    RETURN_IF_DATUM_IS_STRING(d);

    d = toml_bool_in(curtab, key);
    RETURN_IF_DATUM_IS_BOOLEAN(d);

    d = toml_int_in(curtab, key);
    RETURN_IF_DATUM_IS_INTEGER(d);

    d = toml_double_in(curtab, key);
    RETURN_IF_DATUM_IS_DOUBLE(d);

    d = toml_timestamp_in(curtab, key);
    RETURN_IF_DATUM_IS_TIMESTAMP(d);

    /* This indicates some unspecified parse error that the initial
       parse didn’t catch.
    */
    return NULL;
}

SV* _toml_array_value_to_sv(pTHX_ toml_array_t* curarr, int i, AV** err_path_ptr) {
    toml_array_t* arr;
    toml_table_t* tab;

    if (0 != (arr = toml_array_at(curarr, i))) {
        return _toml_array_to_sv(aTHX_ arr, err_path_ptr);
    }

    if (0 != (tab = toml_table_at(curarr, i))) {
        return _toml_table_to_sv(aTHX_ tab, err_path_ptr);
    }

    toml_datum_t d;

    d = toml_string_at(curarr, i);
    RETURN_IF_DATUM_IS_STRING(d);

    d = toml_bool_at(curarr, i);
    RETURN_IF_DATUM_IS_BOOLEAN(d);

    d = toml_int_at(curarr, i);
    RETURN_IF_DATUM_IS_INTEGER(d);

    d = toml_double_at(curarr, i);
    RETURN_IF_DATUM_IS_DOUBLE(d);

    d = toml_timestamp_at(curarr, i);
    RETURN_IF_DATUM_IS_TIMESTAMP(d);

    /* This indicates some unspecified parse error that the initial
       parse didn’t catch.
    */
    return NULL;
}

static void _warn_if_global_destruct_destroy( pTHX_ SV* obj ) {
    if (_IS_GLOBAL_DESTRUCT) {
        warn( "%" SVf " destroyed at global destruction; memory leak likely!\n", obj);
    }
}

/* for profiling: */
/*
#include <sys/time.h>

void _print_timeofday(char* label) {
    struct timeval tp;

    gettimeofday(&tp, NULL);
    fprintf(stderr, "%s: %ld.%06d\n", label, tp.tv_sec, tp.tv_usec);
}
*/

typedef union {
    toml_table_t*       table_p;
    toml_array_t*       array_p;
    toml_datum_t        datum;
} entity_t;

typedef struct {
    entity_t entity;

    enum toml_xs_type   type;
} toml_entity_t;

toml_entity_t _drill_into_array(pTHX_ toml_array_t* arrin, SV** stack, unsigned stack_idx, unsigned drill_len, AV** err_path_ptr);

toml_entity_t _drill_into_table(pTHX_ toml_table_t* tabin, SV** stack, unsigned stack_idx, unsigned drill_len, AV** err_path_ptr) {
    toml_entity_t newent;

    SV* key_sv = stack[stack_idx];

    if (!SvOK(key_sv)) {
        croak("Undef given in lookup (#%d)!", stack_idx);
    }

    char* key = SvPVutf8_nolen(key_sv);

    toml_table_t* tab = toml_table_in(tabin, key);

    if (tab) {
        if (stack_idx == drill_len-1) {
            newent.type = TOML_XS_TYPE_TABLE;
            newent.entity.table_p = tab;
            return newent;
        }
        else {
            return _drill_into_table(aTHX_ tab, stack, 1 + stack_idx, drill_len, err_path_ptr);
        }
    }

    toml_array_t* arr = toml_array_in(tabin, key);

    if (arr) {
        if (stack_idx == drill_len-1) {
            newent.type = TOML_XS_TYPE_ARRAY;
            newent.entity.array_p = arr;
            return newent;
        }
        else {
            return _drill_into_array(aTHX_ arr, stack, 1 + stack_idx, drill_len, err_path_ptr);
        }
    }

    if (stack_idx != drill_len-1) {
        croak("pointer too deep!");
    }

    newent.entity.datum = toml_string_in(tabin, key);

    if (newent.entity.datum.ok) {
        newent.type = TOML_XS_TYPE_STRING;
    }
    else {
        newent.entity.datum = toml_bool_in(tabin, key);

        if (newent.entity.datum.ok) {
            newent.type = TOML_XS_TYPE_BOOLEAN;
        }
        else {
            newent.entity.datum = toml_int_in(tabin, key);

            if (newent.entity.datum.ok) {
                newent.type = TOML_XS_TYPE_INTEGER;
            }
            else {
                newent.entity.datum = toml_double_in(tabin, key);

                if (newent.entity.datum.ok) {
                    newent.type = TOML_XS_TYPE_DOUBLE;
                }
                else {
                    newent.entity.datum = toml_timestamp_in(tabin, key);

                    if (newent.entity.datum.ok) {
                        newent.type = TOML_XS_TYPE_TIMESTAMP;
                    }
                    else {
                        // TODO: distinguish between invalid & missing
                        croak("invalid or missing in table");
                    }
                }
            }
        }
    }

    return newent;
}

toml_entity_t _drill_into_array(pTHX_ toml_array_t* arrin, SV** stack, unsigned stack_idx, unsigned drill_len, AV** err_path_ptr) {
    toml_entity_t newent;

    int i;

    SV* key_sv = stack[stack_idx];

    if (SvUOK(key_sv)) {
        i = SvUV(key_sv);
    }
    else if (!SvOK(key_sv)) {
        croak("Undef given as array index!");
    }
    else {
        UV idx_uv;

        if (Perl_grok_atoUV(SvPVbyte_nolen(key_sv), &idx_uv, NULL)) {
            i = idx_uv;
        }
        else {
            croak("Non-numeric “%" SVf "” given as array index!", key_sv);
        }
    }

    toml_table_t* tab = toml_table_at(arrin, i);

    if (tab) {
        if (stack_idx == drill_len-1) {
            newent.type = TOML_XS_TYPE_TABLE;
            newent.entity.table_p = tab;
            return newent;
        }
        else {
            return _drill_into_table( aTHX_ tab, stack, 1 + stack_idx, drill_len, err_path_ptr);
        }
    }

    toml_array_t* arr = toml_array_at(arrin, i);

    if (arr) {
        if (stack_idx == drill_len-1) {
            newent.type = TOML_XS_TYPE_ARRAY;
            newent.entity.array_p = arr;
            return newent;
        }
        else {
            return _drill_into_array( aTHX_ arr, stack, 1 + stack_idx, drill_len, err_path_ptr);
        }
    }

    if (stack_idx != drill_len-1) {
        croak("pointer too deep!");
    }

    newent.entity.datum = toml_string_at(arrin, i);

    if (newent.entity.datum.ok) {
        newent.type = TOML_XS_TYPE_STRING;
    }
    else {
        newent.entity.datum = toml_bool_at(arrin, i);

        if (newent.entity.datum.ok) {
            newent.type = TOML_XS_TYPE_BOOLEAN;
        }
        else {
            newent.entity.datum = toml_int_at(arrin, i);

            if (newent.entity.datum.ok) {
                newent.type = TOML_XS_TYPE_INTEGER;
            }
            else {
                newent.entity.datum = toml_double_at(arrin, i);

                if (newent.entity.datum.ok) {
                    newent.type = TOML_XS_TYPE_DOUBLE;
                }
                else {
                    newent.entity.datum = toml_timestamp_at(arrin, i);

                    if (newent.entity.datum.ok) {
                        newent.type = TOML_XS_TYPE_TIMESTAMP;
                    }
                    else {
                        croak("Invalid/missing array index: %" SVf, key_sv);
                        // TODO: distinguish between invalid & missing
                    }
                }
            }
        }
    }

    return newent;
}

/* ---------------------------------------------------------------------- */

MODULE = TOML::XS     PACKAGE = TOML::XS

PROTOTYPES: DISABLE

SV*
from_toml (SV* tomlsv)
    CODE:
        STRLEN tomllen;
        char errbuf[200];
        char* tomlstr = SvPVbyte(tomlsv, tomllen);

        _verify_no_null(tomlstr, tomllen);

        _verify_valid_utf8(tomlstr, tomllen);

        toml_table_t* tab = toml_parse(tomlstr, errbuf, sizeof(errbuf));

        if (tab == NULL) croak("%s", errbuf);

        RETVAL = _ptr_to_svrv( aTHX_ tab, gv_stashpv(DOCUMENT_CLASS, FALSE) );
    OUTPUT:
        RETVAL

# ----------------------------------------------------------------------

MODULE = TOML::XS     PACKAGE = TOML::XS::Document

PROTOTYPES: DISABLE

SV*
parse (SV* docsv, ...)
    ALIAS:
        to_struct = 1
    CODE:
        toml_table_t* tab = _get_toml_table_from_sv(aTHX_ docsv);

        AV* err_path = NULL;

        if (items > 1) {
            toml_entity_t root_entity = _drill_into_table(aTHX_ tab, &ST(1), 0, items-1, &err_path);

            switch (root_entity.type) {
                case TOML_XS_TYPE_INVALID:
                    RETVAL = NULL;
                    break;
                case TOML_XS_TYPE_TABLE:
                    RETVAL = _toml_table_to_sv(aTHX_ root_entity.entity.table_p, &err_path);
                    break;

                case TOML_XS_TYPE_ARRAY:
                    RETVAL = _toml_array_to_sv(aTHX_ root_entity.entity.array_p, &err_path);
                    break;

                case TOML_XS_TYPE_STRING:
                    RETVAL = _datum_string_to_sv(aTHX_ root_entity.entity.datum);
                    break;

                case TOML_XS_TYPE_BOOLEAN:
                    RETVAL = _datum_boolean_to_sv(root_entity.entity.datum);
                    break;

                case TOML_XS_TYPE_INTEGER:
                    RETVAL = _datum_integer_to_sv(root_entity.entity.datum);
                    break;

                case TOML_XS_TYPE_DOUBLE:
                    RETVAL = _datum_double_to_sv(root_entity.entity.datum);
                    break;

                case TOML_XS_TYPE_TIMESTAMP:
                    RETVAL = _datum_timestamp_to_sv(root_entity.entity.datum);
                    break;

                default:
                    assert(0);
            }
        }
        else {
            RETVAL = _toml_table_to_sv(aTHX_ tab, &err_path);
        }

        if (NULL == RETVAL) {
            dSP;

            ENTER;
            SAVETMPS;

            PUSHMARK(SP);
            EXTEND(SP, 1);

            /* When this mortal reference is reaped it’ll decrement
               the referent AV’s refcount. */
            mPUSHs(newRV_noinc( (SV*)err_path ));

            PUTBACK;

            call_pv(CROAK_ERR_MSG_FN, G_DISCARD);

            // Unneeded:
            // FREETMPS;
            // LEAVE;

            assert(0);
        }
    OUTPUT:
        RETVAL

void
DESTROY (SV* docsv)
    CODE:
        _warn_if_global_destruct_destroy(aTHX_ docsv);

        toml_table_t* tab = _get_toml_table_from_sv(aTHX_ docsv);
        toml_free(tab);

# ----------------------------------------------------------------------

MODULE = TOML::XS     PACKAGE = TOML::XS::Timestamp

PROTOTYPES: DISABLE

SV*
to_string (SV* selfsv)
    CODE:
        toml_timestamp_t* ts = _get_toml_timestamp_from_sv(aTHX_ selfsv);

        RETVAL = newSVpvs("");

        if (NULL != ts->year) {
            sv_catpvf(
                RETVAL,
                "%02d-%02d-%02d",
                *ts->year, *ts->month, *ts->day
            );
        }

        if (NULL != ts->hour) {
            sv_catpvf(
                RETVAL,
                "T%02d:%02d:%02d",
                *ts->hour, *ts->minute, *ts->second
            );

            if (NULL != ts->millisec) {
                sv_catpvf(
                    RETVAL,
                    ".%03d",
                    *ts->millisec
                );
            }
        }

        if (NULL != ts->z) {
            sv_catpv(RETVAL, ts->z);
        }
    OUTPUT:
        RETVAL

SV*
year (SV* selfsv)
    CODE:
        toml_timestamp_t* ts = _get_toml_timestamp_from_sv(aTHX_ selfsv);

        RETVAL = ts->year ? newSViv(*ts->year) : &PL_sv_undef;
    OUTPUT:
        RETVAL

SV*
month (SV* selfsv)
    CODE:
        toml_timestamp_t* ts = _get_toml_timestamp_from_sv(aTHX_ selfsv);

        RETVAL = ts->month ? newSViv(*ts->month) : &PL_sv_undef;
    OUTPUT:
        RETVAL

SV*
day (SV* selfsv)
    ALIAS:
        date = 1
    CODE:
        UNUSED(ix);
        toml_timestamp_t* ts = _get_toml_timestamp_from_sv(aTHX_ selfsv);

        RETVAL = ts->day ? newSViv(*ts->day) : &PL_sv_undef;
    OUTPUT:
        RETVAL

SV*
hour (SV* selfsv)
    ALIAS:
        hours = 1
    CODE:
        UNUSED(ix);
        toml_timestamp_t* ts = _get_toml_timestamp_from_sv(aTHX_ selfsv);

        RETVAL = ts->hour ? newSViv(*ts->hour) : &PL_sv_undef;
    OUTPUT:
        RETVAL

SV*
minute (SV* selfsv)
    ALIAS:
        minutes = 1
    CODE:
        UNUSED(ix);
        toml_timestamp_t* ts = _get_toml_timestamp_from_sv(aTHX_ selfsv);

        RETVAL = ts->minute ? newSViv(*ts->minute) : &PL_sv_undef;
    OUTPUT:
        RETVAL

SV*
second (SV* selfsv)
    ALIAS:
        seconds = 1
    CODE:
        UNUSED(ix);
        toml_timestamp_t* ts = _get_toml_timestamp_from_sv(aTHX_ selfsv);

        RETVAL = ts->second ? newSViv(*ts->second) : &PL_sv_undef;
    OUTPUT:
        RETVAL

SV*
millisecond (SV* selfsv)
    ALIAS:
        milliseconds = 1
    CODE:
        UNUSED(ix);
        toml_timestamp_t* ts = _get_toml_timestamp_from_sv(aTHX_ selfsv);

        RETVAL = ts->millisec ? newSViv(*ts->millisec) : &PL_sv_undef;
    OUTPUT:
        RETVAL

SV*
timezone (SV* selfsv)
    CODE:
        toml_timestamp_t* ts = _get_toml_timestamp_from_sv(aTHX_ selfsv);

        RETVAL = ts->z ? newSVpv(ts->z, 0) : &PL_sv_undef;
    OUTPUT:
        RETVAL

void
DESTROY (SV* selfsv)
    CODE:
        _warn_if_global_destruct_destroy(aTHX_ selfsv);

        toml_timestamp_t* ts = _get_toml_timestamp_from_sv(aTHX_ selfsv);
        tomlxs_free_timestamp(ts);
