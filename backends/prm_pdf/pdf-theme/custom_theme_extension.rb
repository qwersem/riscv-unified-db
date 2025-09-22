#!/usr/bin/env ruby
# custom_theme_extension.rb
#
# Asciidoctor PDF helper: draws a thin purple line under the title on page 1
# and a small purple square in the bottom-right corner of every page (optionally
# only after the TOC pages). Implemented as a guarded monkeypatch on Prawn::Document.
#
# Usage with Asciidoctor PDF:
#   asciidoctor-pdf \
#     -r path/to/custom_theme_extension.rb \
#     -a pdf-theme=custom your_doc.adoc
#
# Notes
# - This file is safe to require multiple times; the patch is idempotent.
# - If the 'prawn' gem is not available, the decorations are skipped with a warning.

begin
  require 'prawn'
rescue LoadError
  warn '[custom_theme_extension] Prawn is not available; decorations will be disabled.'
end

module CustomPurpleTheme
  # Configuration constants (tweak to your branding/layout)
  LINE_COLOR = '3e058e'            # Hex (without '#')
  LINE_WIDTH = 2                   # Points
  TITLE_TOP_PERCENT = 50           # % of the usable height from top for title baseline
  GAP_AFTER_TITLE = 0              # Extra gap below title baseline (points)
  FALLBACK_OFFSET_FROM_TOP = 140   # If TITLE_TOP_PERCENT is nil, fixed offset (points)

  FOOTER_SQUARES_ENABLED = true
  FOOTER_SQUARE_COLOR = LINE_COLOR
  FOOTER_SQUARE_SIZE = 25       # Points
  FOOTER_SQUARE_COUNT = 1          # Square number
  FOOTER_SQUARE_MARGIN_X = 45       # Inset from right edge (points)
  FOOTER_SQUARE_MARGIN_Y = 17      # Inset from bottom edge (points)
  # Alpha transparency for footer squares (0.0 = fully transparent, 1.0 = opaque)
  FOOTER_SQUARE_ALPHA = 0.5
  # Draw only after the TOC pages. Set to 0 to draw on all pages.
  FOOTER_AFTER_TOC_PAGES = 27

  # Apply the patch to Prawn::Document (idempotent)
  def self.install!
    return unless defined?(::Prawn) && defined?(::Prawn::Document)

    # Use a class instance variable on Prawn::Document to guard against double install
    if ::Prawn::Document.instance_variable_defined?(:@__custom_purple_theme_installed) &&
       ::Prawn::Document.instance_variable_get(:@__custom_purple_theme_installed)
      return
    end

    ::Prawn::Document.instance_variable_set(:@__custom_purple_theme_installed, true)

    ::Prawn::Document.class_eval do
      # Draw the title line only once on the first page.
      def draw_custom_title_line_once
        @__custom_title_line_drawn ||= false
        return if @__custom_title_line_drawn
        if respond_to?(:page_number) && page_number == 1
          begin
            save_graphics_state do
              stroke_color CustomPurpleTheme::LINE_COLOR
              line_width CustomPurpleTheme::LINE_WIDTH

              y = if CustomPurpleTheme::TITLE_TOP_PERCENT
                    bounds.top - (bounds.height * (CustomPurpleTheme::TITLE_TOP_PERCENT.to_f / 100.0)) - CustomPurpleTheme::GAP_AFTER_TITLE
                  else
                    bounds.top - CustomPurpleTheme::FALLBACK_OFFSET_FROM_TOP
                  end

              stroke_horizontal_line bounds.left, bounds.right, at: y
            end
          rescue StandardError => e
            warn "[custom_theme_extension] failed to draw title line: #{e.message}"
          end
          @__custom_title_line_drawn = true
        end
      end

      # Draw footer square (all pages or only after TOC pages depending on config).
      def draw_custom_footer_squares
        return unless CustomPurpleTheme::FOOTER_SQUARES_ENABLED
        if defined?(page_number) && CustomPurpleTheme::FOOTER_AFTER_TOC_PAGES && CustomPurpleTheme::FOOTER_AFTER_TOC_PAGES > 0
          return if page_number <= CustomPurpleTheme::FOOTER_AFTER_TOC_PAGES
        end
        begin
          canvas do
            save_graphics_state do
              prev_fill = respond_to?(:fill_color) ? fill_color : nil
              fill_color CustomPurpleTheme::FOOTER_SQUARE_COLOR

              s = CustomPurpleTheme::FOOTER_SQUARE_SIZE
              start_x = bounds.right - CustomPurpleTheme::FOOTER_SQUARE_MARGIN_X - s
              y_top = bounds.bottom + CustomPurpleTheme::FOOTER_SQUARE_MARGIN_Y + s

              # Draw with optional transparency if supported by Prawn
              if respond_to?(:transparent)
                transparent(CustomPurpleTheme::FOOTER_SQUARE_ALPHA) do
                  fill_rectangle [start_x, y_top], s, s
                end
              else
                # Fallback: opaque fill
                fill_rectangle [start_x, y_top], s, s
              end

              fill_color prev_fill if prev_fill
            end
          end
        rescue StandardError => e
          warn "[custom_theme_extension] failed to draw footer squares: #{e.message}"
        end
      end

      # Hook into page lifecycle. Use alias guards to avoid double aliasing.
      unless method_defined?(:__custom_orig_start_new_page)
        alias_method :__custom_orig_start_new_page, :start_new_page
      end
      def start_new_page(*args, &block)
        __custom_orig_start_new_page(*args, &block)
        draw_custom_title_line_once
        draw_custom_footer_squares
      end

      unless method_defined?(:__custom_orig_initialize)
        alias_method :__custom_orig_initialize, :initialize
      end
      def initialize(*args, &block)
        __custom_orig_initialize(*args, &block)
        draw_custom_title_line_once
        draw_custom_footer_squares
      end
    end
  end
end

# Install immediately when required
CustomPurpleTheme.install!
