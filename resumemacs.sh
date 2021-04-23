#!/usr/bin/env bash

####  CONFIGURABLES  #################################################

readonly DEBUG=0
readonly MAN_HELP=1    # 0=text help, 1=man help
readonly MAN_TYPE=1    # a command by man standards
readonly VERSION="1.0"

# Author metadata
readonly AUTHOR="Joseph Edwards VIII"
readonly AUTHOR_EMAIL="jedwards8th@gmail.com"

####  SELF  ##########################################################

readonly SELF_NAME="${SCRIPT} \- DRY Emacs org-mode résumé builder"
readonly SELF_HELP="Write your résumé in Emacs org-mode then create
versions in PDF, HTML5 and ODT. Tweak and massage locally, then
upload to your webserver to publish!"

SELF_ARGS="ORGFILE"

SELF_OPTS_NOARG="h help v version"
SELF_OPTS="o only p publish c config d dest"
SELF_OPTARGS=( [o]="TYPES" [c]="CFGFILE" [d]="DEST" )
SELF_OPTS_HELP=( \
    [h]="print help message" \
    [v]="print version information" \
    [o]="only convert ORGFILE to TYPES in [pdf, html, odt]" \
    [p]="publish to webserver specified in config" \
    [c]="use external CFGFILE instead of config in ${SCRIPT_SH}" \
    [d]="output directory DEST (default: dirname ORGFILE)" \
    )

####  OPTIONAL MANPAGE  ##############################################

readonly FILES="${SCRIPT} uses Emacs org-mode to export to PDF, and
uses Pandoc to convert the intermediary TEX file to other formats. In
addition it uses external CSS stylesheet and Pandoc templates, which
may be configured internally in ${SCRIPT_SH} or in an external file."
readonly ENVIRONMENT="${SCRIPT} depends on emacs and pandoc. These
commands must be in your path."
readonly EXIT_STATUS="Exits with status \$ERRNO."
readonly EXAMPLE_01="${SCRIPT} /path/to/your_cv.org"
readonly EXAMPLE_02="${SCRIPT} -p -o html -c /path/to/your_cv.conf /path/to/your_cv.org"
readonly EXAMPLES="\&${EXAMPLE_01}\n\n\&${EXAMPLE_02}"
readonly BUGS="Double quotes must be escaped for multiple word paths."
readonly SEE_ALSO=


####  COMMAND FUNCTIONS  #############################################

# Some globals and defaults
readonly DEPS=( emacs pandoc )
readonly TMP_DIR="${SCRIPT_DIR}/tmp"
readonly VALID_EXTS=( pdf html )

readonly CFG_KEYS=( \
    PERSONAL_INFO_TEMPLATES \
    HTML_BASE_TEMPLATE \
    ODT_BASE_TEMPLATE \
    ODT_REFERENCE \
    CSS_LOCAL \
    )
declare -A readonly DEFAULT_FILES=( \
    [PERSONAL_INFO_TEMPLATES]="${SCRIPT_DIR}/etc/personal_info_templates.sh" \
    [HTML_BASE_TEMPLATE]="${SCRIPT_DIR}/etc/default.html5" \
    [ODT_BASE_TEMPLATE]="${SCRIPT_DIR}/etc/default.opendocument" \
    [ODT_REFERENCE]="${SCRIPT_DIR}/etc/odt_reference.odt" \
    [CSS_LOCAL]="${SCRIPT_DIR}/etc/resume.css" \
)

exit_on_error() {
    local errno=$1; shift
    local msg=$1
    if ! _is_zero; then
        _err; _exit_err "$msg"
    fi
}

function check_dependencies {
    for dep in "${DEPS[@]}"; do
        which $dep >/dev/null 2>&1
        exit_on_error $? "$SCRIPT requires $dep"
    done
}

function remake_dir {
    local dir="$1"
    [[ -d  "${dir}" ]] && rm -rf "${dir}"
    mkdir "${dir}"
}

function set_config {
    local cfg_file="$1"

    # Source the personal info + local/remote settings
    source "$cfg_file"

    # If local files not set, then use defaults + check if exist
    for key in "${CFG_KEYS[@]}"; do
        _is_empty "${!key}" \
            && eval "${key}=\"${DEFAULT_FILES[$key]}\""

        if [[ ! -f "${!key}" ]]; then
            _err; _exit_err "file not found: '${!key}'"
        fi
    done
}

function make_info_header {
    local template_var=$1; shift
    local target_info_file="$1"

    echo "${!template_var}" > "$target_info_file"

    [[ -f "$include_before_file" ]]
}

function make_latex_pdf {
    local src_file="$1"; shift
    local target_dir="$1"; shift
    local make_pdf="$1"

    local src_dir=$(dirname "$src_file")
    local src_name=$(basename "${src_file%.*}")
    local header_file="${src_dir}/personal_info.org"

    local ext=pdf
    local export_to=pdf
    local redirect_out=/dev/stdout
    local redirect_err=/dev/stderr

    # export to latex only, or all the way to PDF?
    if [ "$make_pdf" = false ]; then
        ext=tex
        export_to=latex
    fi

    # 1st create the .org header file ...
    echo "$SCRIPT: creating personal info ORG ..."

    make_info_header PERSONAL_INFO_ORG "$header_file"
    exit_on_error $? "file not found: '$header_file'"

    # ... then export org to latex to pdf
    echo "emacs: exporting to $ext ..."
    if _is_zero $DEBUG; then
        redirect_out=/dev/null
        redirect_err=/dev/null
    fi

    emacs \
        -u "$USER" \
        --batch \
        --eval '(load user-init-file)' \
        "$src_file" \
        -f org-latex-export-to-${export_to} \
        >${redirect_out} 2>${redirect_err}

    # Sanity check and move to target dir if different from source dir
    if [[ ! -f "${src_dir}/${src_name}.${ext}" ]]; then
        _err; _exit_err "file not found: '${src_dir}/${src_name}.${ext}'"
    elif ! _str_equal "${src_dir}" "${target_dir}"; then
        mv -f "${src_dir}/${src_name}.${ext}" "${target_dir}"
    fi

    [[ -f "${target_dir}/${src_name}.${ext}" ]]
}

function make_odt {
    local src_file=$1; shift
    local target_dir=$1

    local src_name=$(basename "${src_file%.*}")
    local header_file="${TMP_DIR}/personal_info_odt.xml"
    local target_file="${target_dir}/${src_name}.odt"

    # Make sure LaTEX file exists, else make it ...
    if [[ ! -f "$src_file" ]]; then
        make_latex_pdf "$src_file" "$target_dir" false
        exit_on_error $? "emacs org-latex-export-to-latex failed"
    fi

    # 1st create the .odt header file ...
    echo "$SCRIPT: creating personal info ODT ..."

    make_info_header PERSONAL_INFO_ODT "$header_file"
    exit_on_error $? "file not found: '$header_file'"

    # ... then convert LaTEX to ODT
    echo "pandoc: converting LaTEX to ODT ..."

    pandoc \
        --from=latex \
        --to=odt \
        --template="$ODT_BASE_TEMPLATE" \
        --reference-doc="$ODT_REFERENCE" \
        --include-before-body="$header_file" \
        --output="$target_file" \
        "$src_file"

    [[ -f "$target_file" ]]
}

function make_html {
    local src_file=$1; shift
    local target_dir=$1; shift
    local publish=$1

    local src_dir=$(dirname "$src_file")
    local src_name=$(basename "${src_file%.*}")
    local header_file="${TMP_DIR}/personal_info.html"
    local target_file="${target_dir}/${src_name}.html"
    local stylesheet="$CSS_LOCAL"

    # Make sure LaTEX file exists, else make it ...
    if [[ ! -f "$src_file" ]]; then
        make_latex_pdf "$src_file" "$target_dir" false
        exit_on_error $? "emacs org-latex-export-to-latex failed"
    fi

    # If publishing, then use CSS_REMOTE instead
    [ "$publish" = true ] && stylesheet="$CSS_REMOTE"

    # 1st create the .html header file ...
    echo "$SCRIPT: creating personal info HTML ..."

    make_info_header PERSONAL_INFO_HTML "$header_file"
    exit_on_error $? "file not found: '$header_file'"

    # ... then convert LaTEX to HTML5
    echo "pandoc: converting LaTEX to HTML5 ..."

    pandoc \
        --standalone \
        --from=latex \
        --to=html5 \
        --template="$HTML_BASE_TEMPLATE" \
        --include-before-body="$header_file" \
        --css="$stylesheet" \
        --output="$target_file" \
        "$src_file"

    [[ -f "$target_file" ]]
}

function rsync_publish {
    local target_dir="$1"
    local sync_dir="${SCRIPT_DIR}/sync"

    # create sync dir
    remake_dir "$sync_dir"

    # collect files to upload
    cp "$CSS_LOCAL" "$sync_dir"

    for ext in "${VALID_EXTS[@]}"; do
        cp "${target_dir}"/*.${ext} "$sync_dir/"
    done

    # send it off!
    echo "rsync: uploading files to '$WEBSERVER' ..."
    rsync -av "$sync_dir/" "$WEBSERVER"
}

# _run_self: like 'main()' for self-as-command mode in shkeleton
function _run_self {
    local target_dir=
    local make_only=
    local publish=false

    # Some options require immediate action
    for opt in "${OPTS[@]}"; do
        case $opt in
            h)  _print_help; _exit_err ;;
            v)  echo "$SCRIPT $VERSION"; _exit_err ;;
            d)  target_dir=$( _trim "${OPTARGS[d]}" ) ;;
            c)  cfg_file=$( _trim "${OPTARGS[c]}" ) ;;
            p)  publish=true ;;
            o)
                eval make_only=$( _trim "${OPTARGS[o]}" )
                make_only=( ${make_only[@]} )
                ;;
        esac
    done

    check_dependencies

    # The source ORGFILE
    local eval src_file=${ARGS[ORGFILE]}
    if [[ ! -f "$src_file" ]]; then
       _err; _exit_err "File not found: $src_file"
    fi
    src_file=$(readlink -m "$src_file")
    src_dir=$(dirname "$src_file")
    src_name=$(basename "${src_file%.*}")

    # The target DEST directory
    _is_empty "$target_dir" \
        && target_dir="$src_dir" \
        || target_dir=$(readlink -m "$target_dir")
    [[ ! -d "$target_dir" ]] && mkdir "$target_dir"

    # The temporary build directory
    remake_dir "$TMP_DIR"

    # The config file - personal info + local/remote settings
    _is_empty "$cfg_file" && cfg_file="${src_dir}/${src_name}.sh"
    if [[ ! -f "$cfg_file" ]]; then
        _err; _exit_err "config file not found: '${cfg_file}'"
    fi
    set_config "$cfg_file"

    # Source the personal info header templates
    source "$PERSONAL_INFO_TEMPLATES"

    # Make PDF?
    if _is_empty $make_only || _in_array "pdf" make_only[@]; then
        make_latex_pdf "$src_file" "$target_dir" true
        exit_on_error $? "emacs org-latex-export-to-pdf failed"
    fi

    # Make ODT?
    if _is_empty $make_only || _in_array "odt" make_only[@]; then
        make_odt "${src_dir}/${src_name}.tex" "$target_dir"
        exit_on_error "pandoc latex to odt conversion failed"
    fi

    # Make HTML?
    if _is_empty $make_only || _in_array "html" make_only[@]; then
        make_html "${src_dir}/${src_name}.tex" "$target_dir" $publish
        exit_on_error "pandoc latex to html conversion failed"
    fi

    # Publish?
    [ "$publish" = true ] && rsync_publish "$target_dir"

    printf "\nSUCCESS!\n"
}
