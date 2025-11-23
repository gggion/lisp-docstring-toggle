;;; lisp-docstring-toggle.el --- Toggle Lisp docstring visibility -*- lexical-binding: t -*-

;; Author: Gino Cornejo
;; Mantainer: Gino Cornejo <gggion123@gmail.com>
;; Version: 1.1.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: lisp, docs, editing
;; URL: https://github.com/gggion/lisp-docstring-toggle

;; SPDX-License-Identifier: GPL-3.0-or-later

;; This file is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published
;; by the Free Software Foundation, either version 3 of the License,
;; or (at your option) any later version.
;;
;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this file.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; This package provides commands to toggle the visibility of Lisp
;; docstrings in code buffers.  It works with any major mode that uses
;; `font-lock-doc-face' for docstring highlighting and supports standard
;; s-expression navigation.
;;
;; The core idea is to reduce visual clutter when reviewing code structure,
;; refactoring, or studying codebases while keeping documentation readily
;; available when needed.
;;
;; The package uses Emacs overlays to hide text non-destructively: buffer
;; content is never modified, and all changes are purely visual.
;;
;; Key features:
;;
;; * Buffer-wide toggling of all docstrings
;; * Point-specific toggling of individual docstrings
;; * Configurable hiding styles (complete, partial, first-line)
;; * Debug mode to inspect detected docstrings
;; * Works with mixed fontification (like hl-todo)
;;
;; The detection algorithm is robust: it uses font-lock to identify
;; docstrings, then parses string literal boundaries to handle escaped
;; quotes and face splits correctly.  This works reliably across Emacs Lisp,
;; Common Lisp, Scheme, and other Lisp dialects.
;;
;; Basic usage:
;;
;;     M-x lisp-docstring-toggle           ; Toggle all docstrings
;;     M-x lisp-docstring-toggle-at-point  ; Toggle docstring at point
;;
;; With the minor mode enabled (default bindings):
;;
;;     C-c , t   ; Toggle all docstrings
;;     C-c , .   ; Toggle docstring at point
;;     C-c , D   ; Show debug information
;;
;; The prefix key C-c , can be customized via
;; `lisp-docstring-toggle-keymap-prefix'. For example, if you prefer
;; C-c C-d and it doesn't conflict with your major modes:
;;
;;     (setq lisp-docstring-toggle-keymap-prefix "C-c C-d")
;;
;; Customization:
;;
;; The hiding style is controlled by `lisp-docstring-toggle-hide-style':
;;
;; - `complete': Hide entire docstring (default)
;; - `partial': Show first N characters plus ellipsis
;; - `first-line': Show only first line plus ellipsis
;;
;;
;; The package draws inspiration from several places:
;;
;; - `hideif.el': Overlay-based hiding patterns
;; - `outline.el': Folding interface conventions
;; - `pel-hide-docstring.el': Partial visibility concept
;;
;; For detailed usage and customization, see the docstrings of:
;; - `lisp-docstring-toggle'
;; - `lisp-docstring-toggle-at-point'
;; - `lisp-docstring-toggle-hide-style'
;; - `lisp-docstring-toggle-mode'

;;; Code:
(require 'cl-lib)

;; simple test varible, TODO: create ert tests and move this onto it
(defvar lisp-docstring-toggle--sample-var-to-hide nil
  "A test docstrings.

In childhood, one imagines that any door unopened may open upon a wonder,
a place different from all the places one knows. That is because in childhood it
has so often proved to be so; the child, knowing nothing of any place except
his own, is astonished and delighted by novel sights that an adult would
readily have anticipated. When I was a boy, the doorway of a certain mausoleum
had been a portal of wonder to me; and when I crossed its threshold, I was not
disappointed")

;;;; Customization

(defgroup lisp-docstring-toggle nil
  "Toggle visibility of Lisp docstrings using overlays."
  :group 'lisp
  :prefix "lisp-docstring-toggle-"
  :link '(url-link :tag "Development" "https://github.com/[your-repo]"))

(defcustom lisp-docstring-toggle-ellipsis "[…]"
  "String displayed in place of hidden docstrings.

When nil, no indicator is shown for hidden docstrings.

The ellipsis appears after any visible portion of the docstring,
according to `lisp-docstring-toggle-hide-style'."
  :type '(choice (const :tag "No ellipsis" nil)
          (string :tag "Ellipsis string"))
  :package-version '(lisp-docstring-toggle . "1.0.0")
  :group 'lisp-docstring-toggle)

(defcustom lisp-docstring-toggle-hide-style 'complete
  "How to hide docstrings when toggling visibility.

The value is a symbol, one of:

- `complete': Hide entire docstring content between quotes.  Only the
  ellipsis (if configured) is visible.

- `partial': Show the opening quote, first N characters of content, and
  closing quote.  The number of characters is controlled by
  `lisp-docstring-toggle-partial-chars'.  Useful for getting a quick
  sense of what the docstring contains.

- `first-line': Show the opening quote, first line of content, and
  closing quote.  Useful for docstrings with summary lines.

In all cases, the opening and closing quotes remain visible to maintain
visual context that a string is present.

Examples with a long docstring:

  complete:    \"[…]\"
  partial:     \"This is a comprehensive docstring ex[…]\"
  first-line:  \"This is a comprehensive docstring
               […]\"

The ellipsis indicator is controlled by `lisp-docstring-toggle-ellipsis'."
  :type '(choice (const :tag "Hide completely" complete)
          (const :tag "Show first characters" partial)
          (const :tag "Show first line only" first-line))
  :package-version '(lisp-docstring-toggle . "1.0.0")
  :group 'lisp-docstring-toggle)

(defcustom lisp-docstring-toggle-partial-chars 40
  "Number of characters to show in partial hiding mode.

This applies when `lisp-docstring-toggle-hide-style' is `partial'.

The count includes the opening quote but not the closing quote.
For example, with a value of 40, you might see:

    \"This is a comprehensive docstring ex[…]\"

Where 40 characters of content (plus the opening quote) are visible."
  :type 'integer
  :package-version '(lisp-docstring-toggle . "1.0.0")
  :group 'lisp-docstring-toggle)

;;;; Bindings
(defcustom lisp-docstring-toggle-keymap-prefix "C-c ,"
  "Prefix key sequence for `lisp-docstring-toggle' commands.

The default is \"C-c ,\" which follows Emacs minor mode conventions
\(C-c followed by a punctuation character).

If you prefer a different prefix, you can set this to any key
sequence. For example, if no major mode you use binds C-c C-d,
you might prefer:

    (setq lisp-docstring-toggle-keymap-prefix \"C-c C-d\")

After changing this variable, you must restart
`lisp-docstring-toggle-mode' for the change to take effect."
  :type 'key-sequence
  :package-version '(lisp-docstring-toggle . "1.1.0")
  :group 'lisp-docstring-toggle)


(defvar lisp-docstring-toggle-command-map
  (let ((map (make-sparse-keymap)))
    (define-key map "t" #'lisp-docstring-toggle)
    (define-key map "." #'lisp-docstring-toggle-at-point)
    (define-key map "D" #'lisp-docstring-toggle-debug-show-docstring-snippets)
    map)
  "Keymap for `lisp-docstring-toggle' commands.

This keymap is bound to `lisp-docstring-toggle-keymap-prefix' in
`lisp-docstring-toggle-mode-map'.")

(defvar lisp-docstring-toggle-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd lisp-docstring-toggle-keymap-prefix)
                lisp-docstring-toggle-command-map)
    map)
  "Keymap for `lisp-docstring-toggle-mode'.

\\<lisp-docstring-toggle-mode-map>
\\{lisp-docstring-toggle-mode-map}")

;;;; Internal variables

(defvar-local lisp-docstring-toggle--hidden-p nil
  "Non-nil if docstrings are currently hidden in this buffer.

This is a buffer-local variable used to track the global visibility
state for the buffer.  It is set by `lisp-docstring-toggle' and
consulted to determine whether to hide or show docstrings.")

;;;; Core detection functions

(defun lisp-docstring-toggle--find-docstring-bounds-in-form ()
  "Find and return (BEG . END) of the docstring in the current form.

Search for text with `font-lock-doc-face' within the form containing
point, then compute the actual string literal boundaries.

BEG is the position of the opening quote.
END is the position after the closing quote.

Return nil if:
- Point is not inside any form
- The form has no docstring
- The docstring cannot be parsed

The detection handles:
- Interior face splits from packages like `hl-todo'
- Escaped quotes within docstrings
- Point at the opening parenthesis of a form

This function does not move point."
  (save-excursion
    ;; Handle point at opening paren: move inside the form
    (when (and (looking-at "(")
               (bolp))
      (forward-char 1))

    ;; Verify we're actually inside a form
    (let ((original-point (point))
          (syntax-ppss-data (syntax-ppss)))
      ;; Check if we're inside a list (depth > 0)
      (unless (zerop (nth 0 syntax-ppss-data))
        (let ((form-start (progn (beginning-of-defun) (point)))
              (form-end   (progn (end-of-defun) (point))))
          ;; Verify original point was actually within the form bounds
          (when (and (>= original-point form-start)
                     (<= original-point form-end))
            (goto-char form-start)
            (let ((docstring-start nil)
                  (docstring-end nil))
              ;; Look for any character with doc-face in form.
              (while (and (< (point) form-end)
                          (not docstring-start))
                (when (eq (get-text-property (point) 'face) 'font-lock-doc-face)
                  ;; Found some docstring text, now look for string boundaries.
                  (let ((_here (point)))
                    ;; Search backward for unescaped quote.
                    (while (and (> (point) form-start)
                                (not (char-equal (char-after) ?\")))
                      (backward-char 1))
                    (when (and (>= (point) form-start)
                               (char-equal (char-after) ?\"))
                      (setq docstring-start (point))
                      ;; Forward for closing unescaped quote.
                      (forward-char 1)
                      (while (and (< (point) form-end)
                                  (not (and (char-equal (char-after) ?\")
                                            ;; Unescaped quote only.
                                            (let ((esc 0)
                                                  (chk (1- (point))))
                                              (while (and (>= chk form-start)
                                                          (char-equal (char-after chk) ?\\))
                                                (setq esc (1+ esc))
                                                (setq chk (1- chk)))
                                              (cl-evenp esc)))))
                        (forward-char 1))
                      (when (and (< (point) form-end)
                                 (char-equal (char-after) ?\"))
                        (setq docstring-end (1+ (point))))))

                  (goto-char form-end)) ; break main loop after first detection.

                (unless docstring-start (forward-char 1)))
              (when (and docstring-start docstring-end)
                (cons docstring-start docstring-end)))))))))

(defun lisp-docstring-toggle--collect-all-docstring-bounds ()
  "Return a list of (BEG . END) pairs for all docstrings in the buffer.

Each pair represents the positions of a docstring in a top-level form.
The list is returned in buffer order (earliest to latest).

Sequence:
1. Ensures the entire buffer is fontified via `font-lock-ensure'
2. Searches for top-level forms (lines starting with \"(\")
3. Detect docstrings with `lisp-docstring-toggle--find-docstring-bounds-in-form'
4. Handles malformed forms gracefully by skipping them

The detection takes into account face splits and escaped quotes.  See
`lisp-docstring-toggle--find-docstring-bounds-in-form' for details."
  (let ((docstring-bounds '()))
    (save-excursion
      (save-restriction
        (widen)
        ;; Make sure entire buffer is fontified for doc-face overlays.
        ;; NOTE: font-lock-ensure may be slow on very large buffers (>100k lines).
        ;; This is unavoidable as we need fontification to detect docstrings.
        (font-lock-ensure (point-min) (point-max))
        (goto-char (point-min))
        (while (re-search-forward "^(" nil t)
          (condition-case nil
              (progn
                (when-let ((bounds (lisp-docstring-toggle--find-docstring-bounds-in-form)))
                  (push bounds docstring-bounds))
                (backward-char 1)
                (forward-sexp 1))
            (error (forward-line 1))))))
    (nreverse docstring-bounds)))

;;;; Overlay management

(defun lisp-docstring-toggle--create-overlay (beg end)
  "Create overlay from BEG to END to hide a docstring.

BEG and END are buffer positions delimiting the docstring, including
the opening and closing quote characters.

The overlay respects `lisp-docstring-toggle-hide-style' to determine
what portion of the docstring to hide:

- `complete': Hide all content between quotes
- `partial': Hide content after first N characters
- `first-line': Hide content after first line

The overlay is given the property `lisp-docstring-toggle' set to t for
identification, and uses the invisibility spec `lisp-docstring-toggle'.

If `lisp-docstring-toggle-ellipsis' is non-nil, it is displayed after
the visible portion of the docstring.

Return the created overlay, or nil if there is nothing to hide (for cases where
the docstring is too short for the configured style)."
  (let* ((docstring-text (buffer-substring-no-properties beg end))
         (hide-start beg)
         (hide-end end))

    (pcase lisp-docstring-toggle-hide-style
      ('partial
       ;; Show opening quote + N chars, hide rest, keep closing quote visible
       (let ((visible-chars (min lisp-docstring-toggle-partial-chars
                                 (- (length docstring-text) 2))))
         (when (> visible-chars 0)
           (setq hide-start (+ beg 1 visible-chars))  ; +1 for opening quote
           (setq hide-end (1- end)))))  ; -1 to keep closing quote visible

      ('first-line
       ;; Show opening quote + first line, hide rest, keep closing quote visible
       (let ((first-newline (string-match "\n" docstring-text)))
         (if first-newline
             (progn
               (setq hide-start (+ beg first-newline))
               (setq hide-end (1- end)))
           ;; Single line docstring - don't hide anything
           (setq hide-start end))))

      ('complete
       ;; Hide everything between quotes
       (setq hide-start (1+ beg))
       (setq hide-end (1- end))))

    ;; Only create overlay if there's something to hide
    (when (< hide-start hide-end)
      (let ((overlay (make-overlay hide-start hide-end nil t nil)))
        (overlay-put overlay 'invisible 'lisp-docstring-toggle)
        (overlay-put overlay 'lisp-docstring-toggle t)
        (overlay-put overlay 'evaporate t)
        (when lisp-docstring-toggle-ellipsis
          (overlay-put overlay 'after-string
                       (propertize lisp-docstring-toggle-ellipsis 'face 'shadow)))
        overlay))))

(defun lisp-docstring-toggle--hide-docstrings ()
  "Hide all docstrings in the current buffer with overlays.

Sequence:
1. Removes any existing docstring overlays
2. Adds `lisp-docstring-toggle' to the buffer's invisibility spec
3. Ensures the buffer is fontified
4. Creates overlays for all detected docstrings
5. Sets `lisp-docstring-toggle--hidden-p' to t

The hiding style is controlled by `lisp-docstring-toggle-hide-style'.

This function is called by `lisp-docstring-toggle'.
See also `lisp-docstring-toggle--show-docstrings' for the inverse operation."
  (remove-overlays (point-min) (point-max) 'lisp-docstring-toggle t)
  (add-to-invisibility-spec 'lisp-docstring-toggle)
  (font-lock-ensure (point-min) (point-max))
  (dolist (bounds (lisp-docstring-toggle--collect-all-docstring-bounds))
    (lisp-docstring-toggle--create-overlay (car bounds) (cdr bounds)))
  (setq lisp-docstring-toggle--hidden-p t))

(defun lisp-docstring-toggle--show-docstrings ()
  "Show all docstrings in the buffer by removing overlays.

Sequence:
1. Removes all overlays with the `lisp-docstring-toggle' property
2. Removes `lisp-docstring-toggle' from the invisibility spec
3. Sets `lisp-docstring-toggle--hidden-p' to nil

This function is called by `lisp-docstring-toggle'.
See also `lisp-docstring-toggle--hide-docstrings' for the inverse operation."
  (remove-overlays (point-min) (point-max) 'lisp-docstring-toggle t)
  (remove-from-invisibility-spec 'lisp-docstring-toggle)
  (setq lisp-docstring-toggle--hidden-p nil))

;;;; Interactive commands

;;;###autoload
(defun lisp-docstring-toggle ()
  "Toggle the visibility of all docstrings in the buffer.

When docstrings are visible, hide them.  When hidden, show them.

The hiding style is controlled by `lisp-docstring-toggle-hide-style':
- `complete': Hide entire docstring content
- `partial': Show first N characters (see `lisp-docstring-toggle-partial-chars')
- `first-line': Show only the first line

The ellipsis indicator is controlled by `lisp-docstring-toggle-ellipsis'.

This command uses Emacs overlays to hide text non-destructively.  The
buffer content is never modified, and all changes are reversible.

The detection algorithm works with any major mode that:
1. Uses `font-lock-doc-face' for docstring highlighting
2. Supports standard s-expression navigation

Confirmed to work with `emacs-lisp-mode', `lisp-mode', `scheme-mode',
`clojure-mode', `fennel-mode' and `hy-mode'.

See also:
- `lisp-docstring-toggle-at-point' for toggling individual docstrings
- `lisp-docstring-toggle-debug-show-docstring-snippets' for debugging"
  (interactive)
  (if lisp-docstring-toggle--hidden-p
      (progn
        (lisp-docstring-toggle--show-docstrings)
        (message "Docstrings shown"))
    (lisp-docstring-toggle--hide-docstrings)
    (let ((count (length (lisp-docstring-toggle--collect-all-docstring-bounds))))
      (message "Docstrings hidden (%d found)" count))))

;;;###autoload
(defun lisp-docstring-toggle-at-point ()
  "Toggle visibility of the docstring in the current form at point.

If the docstring is currently hidden (has an overlay), remove the
overlay to show it.  If visible, create an overlay to hide it.

The hiding style respects `lisp-docstring-toggle-hide-style'.

This command is useful for selectively hiding verbose docstrings while
keeping others visible.  It operates only on the form containing point.

If point is:
- At the opening parenthesis of a form: Toggle that form's docstring
- Inside a form: Toggle that form's docstring
- Outside any form: Display an error message

If the current form has no docstring, display an error message.

See also `lisp-docstring-toggle' for buffer-wide toggling."
  (interactive)
  (if-let ((bounds (lisp-docstring-toggle--find-docstring-bounds-in-form)))
      (let ((overlays (overlays-in (car bounds) (cdr bounds))))
        (if (cl-some (lambda (ov) (overlay-get ov 'lisp-docstring-toggle)) overlays)
            (progn
              (remove-overlays (car bounds) (cdr bounds) 'lisp-docstring-toggle t)
              (message "Docstring shown"))
          (add-to-invisibility-spec 'lisp-docstring-toggle)
          (lisp-docstring-toggle--create-overlay (car bounds) (cdr bounds))
          (message "Docstring hidden")))
    (message "No docstring found at point")))

;;;###autoload
(defun lisp-docstring-toggle-debug-show-docstring-snippets ()
  "Open a buffer showing all detected docstrings with navigation links.

This command is useful for:
- Verifying that docstrings are detected correctly
- Navigating to specific docstrings in the source buffer
- Debugging detection issues

The debug buffer shows for each docstring:
- Clickable position links (BEG and END)
- Character count
- First 2 lines of content
- Last 2 lines of content

Clicking a position number jumps to that location in the source buffer.

If no docstrings are found, display a message instead of opening a buffer."
  (interactive)
  (let ((bounds-list (lisp-docstring-toggle--collect-all-docstring-bounds))
        (counter 1)
        (source-buffer (current-buffer)))
    (if bounds-list
        (progn
          (with-output-to-temp-buffer "*Docstring Debug*"
            (with-current-buffer "*Docstring Debug*"
              (insert (format "Found %d docstrings:\n\n" (length bounds-list)))
              (dolist (bounds bounds-list)
                (let* ((start (car bounds))
                       (end (cdr bounds))
                       (docstring (with-current-buffer source-buffer
                                    (buffer-substring-no-properties start end)))
                       (lines (split-string docstring "\n")))
                  (insert (format "=== Docstring %d ===\n" counter))
                  ;; Insert clickable links
                  (insert "Position: ")
                  (insert-text-button (number-to-string start)
                                      'action (lambda (_)
                                                (switch-to-buffer-other-window source-buffer)
                                                (goto-char start)
                                                (recenter))
                                      'help-echo (format "Go to %d" start)
                                      'face 'link)
                  (insert "-")
                  (insert-text-button (number-to-string end)
                                      'action (lambda (_)
                                                (switch-to-buffer-other-window source-buffer)
                                                (goto-char end)
                                                (recenter))
                                      'help-echo (format "Go to %d" end)
                                      'face 'link)
                  (insert (format " (%d chars)\n" (- end start)))
                  (insert "First 2 lines:\n")
                  (dotimes (i (min 2 (length lines)))
                    (insert (format "  %s\n" (nth i lines))))
                  (when (> (length lines) 2)
                    (insert "Last 2 lines:\n")
                    (let ((start-idx (max 0 (- (length lines) 2))))
                      (dotimes (i 2)
                        (let ((line-idx (+ start-idx i)))
                          (when (< line-idx (length lines))
                            (insert (format "  %s\n" (nth line-idx lines))))))))
                  (insert "\n")
                  (cl-incf counter))))
            (pop-to-buffer "*Docstring Debug*"))
          (message "No docstrings found in buffer")))))



;;;; Minor mode
(defun lisp-docstring-toggle--cleanup ()
  "Remove all docstring overlays when buffer is killed.

This function is added to `kill-buffer-hook' by
`lisp-docstring-toggle-mode' to ensure clean buffer cleanup."
  (remove-overlays (point-min) (point-max) 'lisp-docstring-toggle t))

;;;###autoload
(defun lisp-docstring-toggle-setup ()
  "Enable `lisp-docstring-toggle-mode' in Emacs Lisp and Common Lisp modes.

This function checks if the current major mode is derived from
`lisp-mode' or `emacs-lisp-mode', and enables the minor mode if so.

For other Lisp dialects (Scheme, Clojure, Fennel, etc.), use
`lisp-docstring-toggle-mode' directly instead:

    (add-hook \\='scheme-mode-hook #\\='lisp-docstring-toggle-mode)
    (add-hook \\='clojure-mode-hook #\\='lisp-docstring-toggle-mode)
    (add-hook \\='clojure-ts-mode-hook #\\='lisp-docstring-toggle-mode)

The restriction to `lisp-mode' and `emacs-lisp-mode' prevents
accidental activation in non-Lisp buffers when this function is
added to global hooks."
  (when (derived-mode-p 'lisp-mode 'emacs-lisp-mode)
    (lisp-docstring-toggle-mode 1)))


;;;###autoload
(define-minor-mode lisp-docstring-toggle-mode
  "Minor mode for toggling Lisp docstring visibility.

This mode provides keybindings for docstring toggling commands.

Default keybindings (customizable via `lisp-docstring-toggle-keymap-prefix'):

\\<lisp-docstring-toggle-command-map>
\\[lisp-docstring-toggle] - Toggle all docstrings in buffer
\\[lisp-docstring-toggle-at-point] - Toggle docstring at point
\\[lisp-docstring-toggle-debug-show-docstring-snippets] - Show debug information

The default prefix is C-c , but you can customize it. For example,
if C-c C-d doesn't conflict with your major modes:

    (setq lisp-docstring-toggle-keymap-prefix \"C-c C-d\")

The mode also ensures proper cleanup of overlays when the buffer is killed.

Enable this mode automatically in Lisp buffers with:

    (add-hook \\='emacs-lisp-mode-hook #\\='lisp-docstring-toggle-setup)
    (add-hook \\='lisp-mode-hook #\\='lisp-docstring-toggle-setup)"
  :lighter " DocToggle"
  :keymap lisp-docstring-toggle-mode-map
  (if lisp-docstring-toggle-mode
      (add-hook 'kill-buffer-hook #'lisp-docstring-toggle--cleanup nil t)
    (remove-hook 'kill-buffer-hook #'lisp-docstring-toggle--cleanup t)
    (lisp-docstring-toggle--cleanup)))

(provide 'lisp-docstring-toggle)

;;; lisp-docstring-toggle.el ends here
