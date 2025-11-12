# frozen_string_literal: true

require "strscan"
require "stringio"
require "zlib"
require "base64"
require "set"
require "i18n"

require_relative "corp_pdf/dict_scan"
require_relative "corp_pdf/object_resolver"
require_relative "corp_pdf/objstm"
require_relative "corp_pdf/pdf_writer"
require_relative "corp_pdf/incremental_writer"
require_relative "corp_pdf/field"
require_relative "corp_pdf/page"
require_relative "corp_pdf/document"

# Load actions base first (needed by fields)
require_relative "corp_pdf/actions/base"

# Load fields
require_relative "corp_pdf/fields/base"
require_relative "corp_pdf/fields/radio"
require_relative "corp_pdf/fields/text"
require_relative "corp_pdf/fields/checkbox"
require_relative "corp_pdf/fields/signature"

# Load actions
require_relative "corp_pdf/actions/add_field"
require_relative "corp_pdf/actions/update_field"
require_relative "corp_pdf/actions/remove_field"

module CorpPdf
end
