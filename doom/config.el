;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

;; Place your private configuration here! Remember, you do not need to run 'doom
;; sync' after modifying this file!


;; Some functionality uses this to identify you, e.g. GPG configuration, email
;; clients, file templates and snippets. It is optional.
;; (setq user-full-name "John Doe"
;;       user-mail-address "john@doe.com")

;; Doom exposes five (optional) variables for controlling fonts in Doom:
;;
;; - `doom-font' -- the primary font to use
;; - `doom-variable-pitch-font' -- a non-monospace font (where applicable)
;; - `doom-big-font' -- used for `doom-big-font-mode'; use this for
;;   presentations or streaming.
;; - `doom-symbol-font' -- for symbols
;; - `doom-serif-font' -- for the `fixed-pitch-serif' face
;;
;; See 'C-h v doom-font' for documentation and more examples of what they
;; accept. For example:
;;
;;(setq doom-font (font-spec :family "Fira Code" :size 12 :weight 'semi-light)
;;      doom-variable-pitch-font (font-spec :family "Fira Sans" :size 13))
;;
;; If you or Emacs can't find your font, use 'M-x describe-font' to look them
;; up, `M-x eval-region' to execute elisp code, and 'M-x doom/reload-font' to
;; refresh your font settings. If Emacs still can't find your font, it likely
;; wasn't installed correctly. Font issues are rarely Doom issues!

;; There are two ways to load a theme. Both assume the theme is installed and
;; available. You can either set `doom-theme' or manually load a theme with the
;; `load-theme' function. This is the default:
;; (setq doom-theme 'doom-one)
(setq doom-theme 'doom-gruvbox)
;; (setq doom-theme 'doom-ayu-dark)

;; This determines the style of line numbers in effect. If set to `nil', line
;; numbers are disabled. For relative line numbers, set this to `relative'.
;; (setq display-line-numbers-type t)
(setq display-line-numbers-type 'relative)

;; If you use `org' and don't want your org files in the default location below,
;; change `org-directory'. It must be set before org loads!
(setq org-directory "~/org/")


;; Whenever you reconfigure a package, make sure to wrap your config in an
;; `with-eval-after-load' block, otherwise Doom's defaults may override your
;; settings. E.g.
;;
;;   (with-eval-after-load 'PACKAGE
;;     (setq x y))
;;
;; The exceptions to this rule:
;;
;;   - Setting file/directory variables (like `org-directory')
;;   - Setting variables which explicitly tell you to set them before their
;;     package is loaded (see 'C-h v VARIABLE' to look them up).
;;   - Setting doom variables (which start with 'doom-' or '+').
;;
;; Here are some additional functions/macros that will help you configure Doom.
;;
;; - `load!' for loading external *.el files relative to this one
;; - `add-load-path!' for adding directories to the `load-path', relative to
;;   this file. Emacs searches the `load-path' when you load packages with
;;   `require' or `use-package'.
;; - `map!' for binding new keys
;;
;; To get information about any of these functions/macros, move the cursor over
;; the highlighted symbol at press 'K' (non-evil users must press 'C-c c k').
;; This will open documentation for it, including demos of how they are used.
;; Alternatively, use `C-h o' to look up a symbol (functions, variables, faces,
;; etc).
;;
;; You can also try 'gd' (or 'C-c c d') to jump to their definition and see how
;; they are implemented.

;; ==========================================
;; 1. Core & Editor Environment Settings
;; ==========================================

;; Use Bash internally for sub-processes (Fixes Fish shell issues)
(setq shell-file-name (executable-find "bash"))

;; Exit Confirmations
(setq confirm-kill-emacs nil)     ; Stop exit confirmation prompt
(setq confirm-kill-processes nil) ; Stop active background process warnings

;; Line Formatting & Navigation
(setq-default truncate-lines nil)       ; Line wrapping (wrap = true)
(setq evil-ex-search-highlight-all nil) ; Disable persistent search highlights
(setq scroll-margin 8)                  ; Scroll padding (scrolloff = 8)

;; Highlight on Yank (evil-goggles)
(after! evil-goggles
  (setq evil-goggles-duration 0.200) ;; Highlight duration in seconds (200ms)
  (evil-goggles-use-diff-faces))     ;; Green for yank, red for delete

;; Include '@' in 'gf' path lookup (isfname += @-@)
(after! ffap
  (add-to-list 'ffap-string-at-point-mode-alist '(file "\\b[a-zA-Z0-9_./@~-]+\\b")))

(after! dirvish
  ;; Force Dirvish sidebar to open on the right side with 35 columns
  (setq dirvish-side-display-alist '((side . right) (slot . -1)))

  ;; Set the width of the sidebar
  (setq dirvish-side-width 50)

  ;; Enable Follow Mode (Sidebar automatically highlights whichever file you are editing)
  (dirvish-side-follow-mode 1)

  ;; Auto-close sidebar when you press RET to open a file
  (defun my/dirvish-side-open-and-close ()
    "Open selected file and close dirvish-side."
    (interactive)
    (let ((side-win (selected-window)))
      (call-interactively #'dired-find-file)
      (when (and (window-live-p side-win)
                 (not (eq side-win (selected-window))))
        (delete-window side-win))))

  ;; Remap RET inside Dirvish to use the auto-close function
  (map! :map dirvish-mode-map
        :n "RET"      #'my/dirvish-side-open-and-close
        :n "<return>" #'my/dirvish-side-open-and-close))

;; ==========================================
;; 2. System Clipboard Integration
;; ==========================================

;; Decouple regular y/d from system clipboard
(setq select-enable-clipboard nil)
(setq interprogram-cut-function #'ignore)
(setq interprogram-paste-function #'ignore)

;; Operator for SPC y -> Forces register ?+ and triggers doom/system-copy
(evil-define-operator doom/evil-yank-to-system (beg end type _register yank-handler)
  "Yank text over BEG and END explicitly to system clipboard."
  :move-point nil
  (interactive "<R><x>")
  (let ((text (buffer-substring-no-properties beg end)))
    (evil-yank beg end type ?+ yank-handler)
    (doom/system-copy text)))

;; Operator for SPC d -> Forces register ?_ (blackhole)
(evil-define-operator doom/evil-delete-blackhole (beg end type _register yank-handler)
  "Delete text over BEG and END explicitly to blackhole register."
  :move-point nil
  (interactive "<R><x>")
  (evil-delete beg end type ?_ yank-handler))

;; ==========================================
;; 3. Custom Helper Functions
;; ==========================================

;; Provider function for system & tmux clipboard
(defun doom/system-copy (text &optional _push)
  "Send TEXT to system clipboard AND tmux buffer synchronously."
  (when (and text (not (string-empty-p text)))
    (let ((clean-text (substring-no-properties text)))

      ;; 1. Sync with Termux / OS Clipboard
      (cond
       ((executable-find "termux-clipboard-set")
        (with-temp-buffer
          (insert clean-text)
          (call-process-region (point-min) (point-max) "termux-clipboard-set")))

       ((executable-find "wl-copy")
        (with-temp-buffer
          (insert clean-text)
          (call-process-region (point-min) (point-max) "wl-copy")))

       ((executable-find "pbcopy")
        (with-temp-buffer
          (insert clean-text)
          (call-process-region (point-min) (point-max) "pbcopy")))

       ((executable-find "xclip")
        (with-temp-buffer
          (insert clean-text)
          (call-process-region (point-min) (point-max) "xclip" nil nil nil "-selection" "clipboard"))))

      ;; 2. Sync with Tmux Buffer
      (when (getenv "TMUX")
        (with-temp-buffer
          (insert clean-text)
          (call-process-region (point-min) (point-max) "tmux" nil nil nil "load-buffer" "-w" "-"))))))

;; Visual Paste for SPC p -> Deletes region to ?_ and pastes default register ?\"
(defun doom/evil-paste-no-clobber ()
  "Paste over visual selection without replacing the copy buffer."
  (interactive)
  (when (evil-visual-state-p)
    (evil-delete (region-beginning) (region-end) 'visual ?_)
    (evil-paste-before 1 ?\")))

(defun my/insert-markdown-code-block ()
  "Insert triple-backtick markdown block."
  (interactive)
  (insert "```\n```")
  (forward-line -1)
  (end-of-line))


;; ==========================================
;; 4. Keybindings (`map!`)
;; ==========================================

;; Normal, Visual & Insert Mode Bindings
(map!
 :n "C-d" (cmd! (evil-scroll-down nil) (evil-scroll-line-to-center nil))
 :n "C-u" (cmd! (evil-scroll-up nil) (evil-scroll-line-to-center nil))
 :n "n"   (cmd! (evil-ex-search-next) (evil-scroll-line-to-center nil))
 :n "N"   (cmd! (evil-ex-search-previous) (evil-scroll-line-to-center nil))

 :i "M-`" #'my/insert-markdown-code-block)

;; Leader Bindings (<leader>)
(map! :leader
      :desc "Yank to system clipboard" :nv "y" #'doom/evil-yank-to-system
      :desc "Delete to blackhole"      :nv "d" #'doom/evil-delete-blackhole
      :desc "Paste over (no clobber)"  :v  "p" #'doom/evil-paste-no-clobber
      :desc "Toggle file manager"      :n  "e" #'dirvish-side)
