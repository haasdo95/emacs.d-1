;;; init.el --- Nasy's emacs.d init file.            -*- lexical-binding: t; -*-
;; Copyright (C) 2018  Nasy

;; Author: Nasy <echo bmFzeXh4QGdtYWlsLmNvbQo= | base64 -d (or -D on macOS)>

;;; Commentary:

;; Nasy's emacs.d init file.  For macOS and Emacs 26.

;;; Code:
(setq debug-on-error t
      message-log-max t
      load-prefer-newer t)
(setq-default lexical-binding t
              ad-redefinition-action 'accept)

(defconst *is-a-mac* (eq system-type 'darwin))

(defconst emacs-start-init-time (current-time))

(add-hook 'after-init-hook #'(lambda () (message "After init-hook in %.2fms"
                                            (benchmark-init/time-subtract-millis
                                             (current-time)
                                             emacs-start-init-time))))
;; For straight
;;----------------------------------------------------------------------------

(setq straight-recipes-gnu-elpa-use-mirror t
      straight-repository-branch           "develop")

(defvar bootstrap-version)
(let ((bootstrap-file
       (expand-file-name "straight/repos/straight.el/bootstrap.el" user-emacs-directory))
      (bootstrap-version 5))
  (unless (file-exists-p bootstrap-file)
    (with-current-buffer
        (url-retrieve-synchronously
         "https://raw.githubusercontent.com/raxod502/straight.el/develop/install.el"
         'silent 'inhibit-cookies)
      (goto-char (point-max))
      (eval-print-last-sexp)))
  (load bootstrap-file nil 'nomessage))

;; Adjust garbage collection thresholds during startup, and thereafter
;;----------------------------------------------------------------------------

(let ((normal-gc-cons-threshold (* 256 1024 1024))
      (init-gc-cons-threshold (* 512 1024 1024)))
  (setq gc-cons-threshold init-gc-cons-threshold)
  (add-hook 'after-init-hook
            (lambda ()
              (setq gc-cons-threshold normal-gc-cons-threshold))))

;; For use-package
;;----------------------------------------------------------------------------

(straight-use-package 'use-package)

;; Benchmark
;;----------------------------------------------------------------------------

(use-package benchmark-init
  :demand t
  :straight t
  :hook ((after-init . benchmark-init/deactivate)))


;; Reload the init-file
;;----------------------------------------------------------------------------

(defun radian-reload-init ()
  "Reload init.el."
  (interactive)
  (straight-transaction
    (straight-mark-transaction-as-init)
    (message "Reloading init.el...")
    (load user-init-file nil 'nomessage)
    (message "Reloading init.el... done.")))


(defun radian-eval-buffer ()
  "Evaluate the current buffer as Elisp code."
  (interactive)
  (message "Evaluating %s..." (buffer-name))
  (straight-transaction
    (if (null buffer-file-name)
        (eval-buffer)
      (when (string= buffer-file-name user-init-file)
        (straight-mark-transaction-as-init))
      (load-file buffer-file-name)))
  (message "Evaluating %s... done." (buffer-name)))

(unwind-protect
    (let ((straight-treat-as-init t))
      "load your init-file here")
  (straight-finalize-transaction))

;; Expand load-path
;;----------------------------------------------------------------------------

(add-to-list 'load-path (expand-file-name "lisp" user-emacs-directory))
(add-to-list 'load-path (expand-file-name "config" user-emacs-directory))


;; Some config.
;;----------------------------------------------------------------------------

(defvar nasy:config-before-hook nil
  "Hooks to run config functions before load custom.el.")

(defvar nasy:config-after-hook nil
  "Hooks to run config functions after." )

(add-hook 'nasy:config-after-hook #'(lambda () (message "Hi~ Hoop you have fun with this config.")))
(add-hook 'after-init-hook #'(lambda () (run-hooks 'nasy:config-after-hook)))

(require 'nasy-config nil t)
(require 'user-config nil t)


;; Theme
;;----------------------------------------------------------------------------

(use-package doom-themes
  :demand t
  :straight t
  :config
  (load-theme nasy:theme t)
  ;; (doom-themes-treemacs-config)  ;; The doom theme havn't finished it yet.
  (doom-themes-visual-bell-config)
  (doom-themes-org-config))


;; Compile
;;----------------------------------------------------------------------------

(use-package async
  :straight t
  :config
  (dired-async-mode 1)
  (async-bytecomp-package-mode 1))

(use-package auto-compile
  :demand t
  :straight t
  :config
  (auto-compile-on-load-mode)
  (auto-compile-on-save-mode))

(setq-default compilation-scroll-output t)

(use-package alert
  :demand t
  :straight t
  :preface
  (defun alert-after-compilation-finish (buf result)
    "Use `alert' to report compilation RESULT if BUF is hidden."
    (when (buffer-live-p buf)
      (unless (catch 'is-visible
                (walk-windows (lambda (w)
                                (when (eq (window-buffer w) buf)
                                  (throw 'is-visible t))))
                nil)
        (alert (concat "Compilation " result)
               :buffer buf
               :category 'compilation)))))


(use-package compile
  :demand t
  :preface
  (defvar last-compilation-buffer nil
    "The last buffer in which compilation took place.")

  (defadvice compilation-start (after save-compilation-buffer activate)
    "Save the compilation buffer to find it later."
    (setq last-compilation-buffer next-error-last-buffer))

  (defadvice recompile (around find-prev-compilation (&optional edit-command) activate)
    "Find the previous compilation buffer, if present, and recompile there."
    (if (and (null edit-command)
             (not (derived-mode-p 'compilation-mode))
             last-compilation-buffer
             (buffer-live-p (get-buffer last-compilation-buffer)))
        (with-current-buffer last-compilation-buffer
          ad-do-it)
      ad-do-it))
  :bind (([f6] . recompile))
  :hook ((compilation-finish-functions . alert-after-compilation-finish)))


(use-package ansi-color
  :demand t
  :after compile
  :straight t
  :hook ((compilation-filter . colourise-compilation-buffer))
  :config
  (defun colourise-compilation-buffer ()
    (when (eq major-mode 'compilation-mode)
      (ansi-color-apply-on-region compilation-filter-start (point-max)))))

;; Shell
;;----------------------------------------------------------------------------

(require 'shell)

(use-package cmd-to-echo
  :defer t
  :straight t)


(use-package command-log-mode
  :demand t
  :straight t)


(defadvice shell-command-on-region
    (after shell-command-in-view-mode
           (start end command &optional output-buffer replace &rest other-args)
           activate)
  "Put \"*Shell Command Output*\" buffers into view-mode."
  (unless (or output-buffer replace)
    (with-current-buffer "*Shell Command Output*"
      (view-mode 1))))


(use-package exec-path-from-shell
  :demand *is-a-mac*
  :straight t
  :preface
  ;; Non-Forking Shell Command To String
  ;; https://github.com/bbatsov/projectile/issues/1044
  ;;--------------------------------------------------------------------------

  (defun call-process-to-string (program &rest args)
    (with-temp-buffer
      (apply 'call-process program nil (current-buffer) nil args)
      (buffer-string)))

  (defun get-call-process-args-from-shell-command (command)
    (cl-destructuring-bind
        (the-command . args) (split-string command " ")
      (let ((binary-path (executable-find the-command)))
        (when binary-path
          (cons binary-path args)))))

  (defun shell-command-to-string (command)
    (let ((call-process-args
           (get-call-process-args-from-shell-command command)))
      (if call-process-args
          (apply 'call-process-to-string call-process-args)
        (shell-command-to-string command))))

  (defun try-call-process (command)
    (let ((call-process-args
           (get-call-process-args-from-shell-command command)))
      (if call-process-args
          (apply 'call-process-to-string call-process-args))))

  (advice-add 'shell-command-to-string :before-until 'try-call-process)

  (defun call-with-quick-shell-command (fn &rest args)
    (noflet ((shell-command-to-string
              (&rest args)
              (or (apply 'try-call-process args) (apply this-fn args))))
            (apply fn args)))

  (advice-add 'projectile-find-file :around 'call-with-quick-shell-command)
  :init (setq shell-command-switch "-ic")
  :config (progn
            (when nil (message "PATH: %s, INFO: %s" (getenv "PATH")
                               (getenv "ENVIRONMENT_SETUP_DONE"))
                  (setq exec-path-from-shell-debug t))
            (setq exec-path-from-shell-arguments (list "-l"))
            (setq exec-path-from-shell-check-startup-files nil)
            (add-to-list 'exec-path-from-shell-variables "SHELL")
            (add-to-list 'exec-path-from-shell-variables "GOPATH")
            (add-to-list 'exec-path-from-shell-variables "ENVIRONMENT_SETUP_DONE")
            (add-to-list 'exec-path-from-shell-variables "PYTHONPATH")
            (exec-path-from-shell-initialize)))


;; Disable some features
;;----------------------------------------------------------------------------

(setq use-file-dialog nil
      use-dialog-box nil
      inhibit-startup-screen t)

(when (fboundp 'tool-bar-mode)
  (tool-bar-mode -1))

(when (fboundp 'set-scroll-bar-mode)
  (set-scroll-bar-mode nil))


;; scratch message
;;----------------------------------------------------------------------------

(use-package scratch
  :demand t
  :straight t)


;; nice scrolling
;;----------------------------------------------------------------------------

(setq scroll-margin 0
      scroll-conservatively 100000
      scroll-preserve-screen-position 'always)


;; dashboard
;;----------------------------------------------------------------------------

(use-package dashboard
  :demand t
  :straight t
  :init (setq dashboard-startup-banner 'official
              dashboard-items '((recents   . 5)
                                (bookmarks . 5)
                                (projects  . 5)
                                (agenda    . 5)
                                (registers . 5)))
  :config (dashboard-setup-startup-hook))


;; Windows
;;----------------------------------------------------------------------------

(add-hook 'after-init-hook 'winner-mode)

(use-package switch-window
  :straight t
  :init (setq-default switch-window-shortcut-style 'alphabet
                      switch-window-timeout nil)
  :bind (("C-x o" . switch-window)))

;; When splitting window, show (other-buffer) in the new window
(defun split-window-func-with-other-buffer (split-function)
  (lambda (&optional arg)
    "Split this window and switch to the new window unless ARG is provided."
    (interactive "P")
    (funcall split-function)
    (let ((target-window (next-window)))
      (set-window-buffer target-window (other-buffer))
      (unless arg
        (select-window target-window)))))

(global-set-key (kbd "C-x 2")
                (split-window-func-with-other-buffer 'split-window-vertically))
(global-set-key (kbd "C-x 3")
                (split-window-func-with-other-buffer 'split-window-horizontally))


(defun toggle-delete-other-windows ()
  "Delete other windows in frame if any, or restore previous window config."
  (interactive)
  (if (and winner-mode
           (equal (selected-window) (next-window)))
      (winner-undo)
    (delete-other-windows)))

(global-set-key (kbd "C-x 1") 'toggle-delete-other-windows)


;; Functions
;;----------------------------------------------------------------------------

(defun nasy:insert-current-date ()
  "Insert current date."
  (interactive)
  (insert (shell-command-to-string "echo -n $(date +'%b %d, %Y')")))

(defun nasy:insert-current-filename ()
  "Insert current buffer filename."
  (interactive)
  (insert (file-relative-name buffer-file-name)))

;; Rearrange split windows

(defun split-window-horizontally-instead ()
  "Kill any other windows and re-split such that the current window is on the
top half of the frame."
  (interactive)
  (let ((other-buffer (and (next-window) (window-buffer (next-window)))))
    (delete-other-windows)
    (split-window-horizontally)
    (when other-buffer
      (set-window-buffer (next-window) other-buffer))))

(defun split-window-vertically-instead ()
  "Kill any other windows and re-split such that the current window is on the
left half of the frame."
  (interactive)
  (let ((other-buffer (and (next-window) (window-buffer (next-window)))))
    (delete-other-windows)
    (split-window-vertically)
    (when other-buffer
      (set-window-buffer (next-window) other-buffer))))

(global-set-key (kbd "C-x |") 'split-window-horizontally-instead)
(global-set-key (kbd "C-x _") 'split-window-vertically-instead)


;; Borrowed from http://postmomentum.ch/blog/201304/blog-on-emacs
(defun nasy/split-window()
  "Split the window to see the most recent buffer in the other window.
Call a second time to restore the original window configuration."
  (interactive)
  (if (eq last-command 'nasy/split-window)
      (progn
        (jump-to-register :nasy:split-window)
        (setq this-command 'nasy/unsplit-window))
    (window-configuration-to-register :nasy/split-window)
    (switch-to-buffer-other-window nil)))

(global-set-key (kbd "<f7>") 'nasy/split-window)


(defun toggle-current-window-dedication ()
  "Toggle whether the current window is dedicated to its current buffer."
  (interactive)
  (let* ((window (selected-window))
         (was-dedicated (window-dedicated-p window)))
    (set-window-dedicated-p window (not was-dedicated))
    (message "Window %sdedicated to %s"
             (if was-dedicated "no longer " "")
             (buffer-name))))

(global-set-key (kbd "C-c <down>") 'toggle-current-window-dedication)



;; Session
;;----------------------------------------------------------------------------
;; desktop save

(setq desktop-path (list user-emacs-directory)
      desktop-auto-save-timeout 600)
(desktop-save-mode 1)


(defadvice desktop-read (around time-restore activate)
    (let ((start-time (current-time)))
      (prog1
          ad-do-it
        (message "Desktop restored in %.2fms"
                 (benchmark-init/time-subtract-millis (current-time)
                                                 start-time)))))


(defadvice desktop-create-buffer (around time-create activate)
  (let ((start-time (current-time))
        (filename (ad-get-arg 1)))
    (prog1
        ad-do-it
      (message "Desktop: %.2fms to restore %s"
               (benchmark-init/time-subtract-millis (current-time)
                                               start-time)
               (when filename
                 (abbreviate-file-name filename))))))


(setq-default history-length 1000)
(add-hook 'after-init-hook 'savehist-mode)


(use-package session
  :defer t
  :straight t
  :hook ((after-init . session-initialize))
  :init
  (setq session-save-file (expand-file-name ".session" user-emacs-directory)
        session-name-disable-regexp "\\(?:\\`'/tmp\\|\\.git/[A-Z_]+\\'\\)"
        session-save-file-coding-system 'utf-8
        desktop-globals-to-save
        (append '((comint-input-ring        . 50)
                  (compile-history          . 30)
                  desktop-missing-file-warning
                  (dired-regexp-history     . 20)
                  (extended-command-history . 30)
                  (face-name-history        . 20)
                  (file-name-history        . 100)
                  (grep-find-history        . 30)
                  (grep-history             . 30)
                  (ido-buffer-history       . 100)
                  (ido-last-directory-list  . 100)
                  (ido-work-directory-list  . 100)
                  (ido-work-file-list       . 100)
                  (ivy-history              . 100)
                  (magit-read-rev-history   . 50)
                  (minibuffer-history       . 50)
                  (org-clock-history        . 50)
                  (org-refile-history       . 50)
                  (org-tags-history         . 50)
                  (query-replace-history    . 60)
                  (read-expression-history  . 60)
                  (regexp-history           . 60)
                  (regexp-search-ring       . 20)
                  register-alist
                  (search-ring              . 20)
                  (shell-command-history    . 50)
                  tags-file-name
                  tags-table-list))))

;; Editor
;;----------------------------------------------------------------------------
;; some default settings

(setq-default
 bookmark-default-file (expand-file-name ".bookmarks.el" user-emacs-directory)
 buffers-menu-max-size 30
 case-fold-search t
 column-number-mode t
 cursor-in-non-selected-windows t
 dired-dwim-target t
 ediff-split-window-function 'split-window-horizontally
 ediff-window-setup-function 'ediff-setup-windows-plain
 indent-tabs-mode nil
 line-move-visual t
 make-backup-files nil
 mouse-yank-at-point t
 require-final-newline t
 save-interprogram-paste-before-kill t
 set-mark-command-repeat-pop t
 tab-always-indent 'complete
 truncate-lines nil
 truncate-partial-width-windows nil)


(delete-selection-mode t)

(fset 'yes-or-no-p 'y-or-n-p)

(global-auto-revert-mode t)

(blink-cursor-mode t)


(use-package diminish
  :demand t
  :straight t)


(use-package which-func
  :demand t
  :hook ((after-init . which-function-mode)))


(use-package disable-mouse
  :straight t
  :bind (([mouse-4] . (lambda ()
                        (interactive)
                        (scroll-down 1)))
         ([mouse-5] . (lambda ()
                        (interactive)
                        (scroll-up 1)))))


(use-package list-unicode-display
  :defer t
  :straight t)


(use-package which-key
  :straight t
  :hook ((after-init . which-key-mode)))


(use-package dash
  :straight t)


(use-package cheat-sh
  :straight t)


(use-package page-break-lines
  :straight t
  :hook ((after-init . global-page-break-lines-mode))
  :diminish page-break-lines-mode)


;; isearch
;;----------------------------------------------------------------------------

(use-package isearch
  :preface
  ;; Search back/forth for the symbol at point
  ;; See http://www.emacswiki.org/emacs/SearchAtPoint
  (defun isearch-yank-symbol ()
    "*Put symbol at current point into search string."
    (interactive)
    (let ((sym (thing-at-point 'symbol)))
      (if sym
          (progn
            (setq isearch-regexp t
                  isearch-string (concat "\\_<" (regexp-quote sym) "\\_>")
                  isearch-message (mapconcat 'isearch-text-char-description isearch-string "")
                  isearch-yank-flag t))
        (ding)))
    (isearch-search-and-update))

  ;; http://www.emacswiki.org/emacs/ZapToISearch
  (defun isearch-exit-other-end (rbeg rend)
    "Exit isearch, but at the other end of the search string.
This is useful when followed by an immediate kill."
    (interactive "r")
    (isearch-exit)
    (goto-char isearch-other-end))

  :bind (:map isearch-mode-map
              ([remap isearch-delete-char] . isearch-del-char)
              ("C-M-w" . isearch-yank-symbol)
              ([(control return)] . isearch-exit-other-end))
  :config
  (when (fboundp 'isearch-occur)
    ;; to match ivy conventions
    (define-key isearch-mode-map (kbd "C-c C-o") 'isearch-occur)))


;; grep
;;----------------------------------------------------------------------------

(setq-default grep-highlight-matches t
              grep-scroll-output t)

(when *is-a-mac*
  (setq-default locate-command "mdfind"))


;; parens
;;----------------------------------------------------------------------------

(add-hook 'after-init-hook 'show-paren-mode)


(use-package smartparens-config
  :defer t
  :straight smartparens
  :hook ((after-init . show-smartparens-global-mode)
         (after-init . smartparens-global-mode))
  :init (setq sp-hybrid-kill-entire-symbol nil))


(use-package rainbow-delimiters
  :defer t
  :straight t
  :hook (((prog-mode text-mode) . rainbow-delimiters-mode)))


;; highlight indention
;;----------------------------------------------------------------------------

(use-package highlight-indent-guides
  :defer t
  :straight t
  :hook (((prog-mode text-mode) . highlight-indent-guides-mode)))


;; dired
;;----------------------------------------------------------------------------

(use-package dired
  :defer t
  :init
  (let ((gls (executable-find "gls")))
    (when gls (setq insert-directory-program gls)))
  :config (setq dired-recursive-deletes 'top)
  (define-key dired-mode-map [mouse-2]       'dired-find-file)
  (define-key dired-mode-map (kbd "C-c C-p") 'wdired-change-to-wdired-mode))


(use-package diredfl
  :defer t
  :after dired
  :straight t
  :hook ((after-init . diredfl-global-mode)))


(use-package uniquify
  :defer t
  :init  ;; nicer naming of buffers for files with identical names
  (setq uniquify-buffer-name-style   'reverse
        uniquify-separator           " • "
        uniquify-after-kill-buffer-p t
        uniquify-ignore-buffers-re   "^\\*"))


(use-package diff-hl
  :defer t
  :after dired
  :straight t
  :hook ((dired-mode . diff-hl-dired-mode)))


;; recentf
;;----------------------------------------------------------------------------

(use-package recentf
  :defer t
  :hook ((after-init . recentf-mode))
  :init (setq-default
         recentf-save-file       "~/.emacs.d/recentf"
         recentf-max-saved-items 100
         recentf-exclude         '("/tmp/" "/ssh:")))

;; smex
;;----------------------------------------------------------------------------

(use-package smex
  :defer t
  :straight t
  :init (setq-default smex-save-file (expand-file-name ".smex-items" user-emacs-directory))
  :bind (("<remap> <execute-extended-command>" . smex)))


;; subword
;;----------------------------------------------------------------------------

(use-package subword
  :defer t
  :diminish (subword-mode))


;; multiple cursors
;;----------------------------------------------------------------------------

(use-package multiple-cursors
  :defer t
  :straight t
  :bind (("C-<"     . mc/mark-previous-like-this)
         ("C->"     . mc/mark-next-like-this)
         ("C-+"     . mc/mark-next-like-this)
         ("C-c C-<" . mc/mark-all-like-this)
         ;; From active region to multiple cursors:
         ("C-c m r" . set-rectangular-region-anchor)
         ("C-c m c" . mc/edit-lines)
         ("C-c m e" . mc/edit-ends-of-lines)
         ("C-c m a" . mc/edit-beginnings-of-lines)))


;; mmm-mode
;;----------------------------------------------------------------------------

(use-package mmm-auto
  :demand t
  :straight mmm-mode
  :init (setq mmm-global-mode 'buffers-with-submode-classes
              mmm-submode-decoration-level 2))


;; whitespace
;;----------------------------------------------------------------------------

(use-package whitespace
  :defer t
  :preface
  (defun no-trailing-whitespace ()
    "Turn off display of trailing whitespace in this buffer."
    (setq show-trailing-whitespace nil))
  :init
  (setq-default show-trailing-whitespace t
                whitespace-style         '(face tabs empty trailing lines-tail))

  ;; But don't show trailing whitespace in SQLi, inf-ruby etc.
  (dolist (hook '(special-mode-hook
                  Info-mode-hook
                  eww-mode-hook
                  term-mode-hook
                  comint-mode-hook
                  compilation-mode-hook
                  twittering-mode-hook
                  minibuffer-setup-hook))
    (add-hook hook #'no-trailing-whitespace))
  :diminish whitespace-mode)


(use-package whitespace-cleanup-mode
  :straight t
  :init (setq whitespace-cleanup-mode-only-if-initially-clean nil)
  :hook ((after-init . global-whitespace-cleanup-mode))
  :diminish (whitespace-cleanup-mode)
  :bind (("<remap> <just-one-space>" . cycle-spacing)))


;; large file
;;----------------------------------------------------------------------------

(use-package vlf
  :defer t
  :straight t
  :init
  (defun ffap-vlf ()
    "Find file at point with VLF."
    (interactive)
    (let ((file (ffap-file-at-point)))
      (unless (file-exists-p file)
        (error "File does not exist: %s" file))
      (vlf file))))


;; text-scale
;;----------------------------------------------------------------------------

(use-package default-text-scale
  :straight t)


;; unfill
;;----------------------------------------------------------------------------

(use-package unfill
  :straight t)


;; visual fill column
;;----------------------------------------------------------------------------

(use-package visual-fill-column
  :defer t
  :straight t
  :preface
  (defun maybe-adjust-visual-fill-column ()
    "Readjust visual fill column when the global font size is modified.
This is helpful for writeroom-mode, in particular."
    (if visual-fill-column-mode
        (add-hook 'after-setting-font-hook 'visual-fill-column--adjust-window nil t)
      (remove-hook 'after-setting-font-hook 'visual-fill-column--adjust-window t)))
  :hook ((visual-line-mode . visual-fill-column-mode)
         (visual-fill-column-mode . maybe-adjust-visual-fill-column)))


;; flycheck
;;----------------------------------------------------------------------------

(use-package flycheck
  :defer t
  :straight t
  :preface
  (defun save-buffer-maybe-show-errors ()
    "Save buffer and show errors if any."
    (interactive)
    (save-buffer)
    (when (not flycheck-current-errors)
      (flycheck-list-errors)))
  :commands (flycheck-mode
             flycheck-next-error
             flycheck-previous-error)
  ;; :bind (("C-x C-s" . save-buffer-maybe-show-errors))
  :hook ((after-init . global-flycheck-mode))
  :init (setq flycheck-display-errors-function
              #'flycheck-display-error-messages-unless-error-list)
  :config (defalias 'show-error-at-point-soon
            'flycheck-show-error-at-point)
  (add-to-list 'flycheck-emacs-lisp-checkdoc-variables 'sentence-end-double-space))


(use-package flycheck-package
  :after flycheck
  :straight t)


;; company
;;----------------------------------------------------------------------------

(use-package company
  :defer t
  :straight t
  :init
  (setq-default company-minimum-prefix-length .2
                company-transformers '(company-sort-by-backend-importance)
                company-require-match nil
                company-tooltip-align-annotations t
                company-dabbrev-other-buffers 'all
                company-dabbrev-downcase nil
                company-dabbrev-ignore-case t
                company-gtags-executable "gtags")
  :hook ((after-init . global-company-mode))
  :bind (("M-C-/" . company-complete)
         :map company-mode-map
         ("M-/"   . company-complete)
         :map company-active-map
         ("M-/"   . company-complete)
         ("<tab>" . company-other-backend)
         ("C-n"   . company-select-next)
         ("C-p"   . company-select-previous))
  :config
  (defvar my-prev-whitespace-mode nil)
  (make-variable-buffer-local 'my-prev-whitespace-mode)
  (defun pre-popup-draw ()
    "Turn off whitespace mode before showing company complete tooltip"
    (if whitespace-mode
        (progn
          (setq my-prev-whitespace-mode t)
          (whitespace-mode -1)
          (setq my-prev-whitespace-mode t))))
  (defun post-popup-draw ()
    "Restore previous whitespace mode after showing company tooltip"
    (if my-prev-whitespace-mode
        (progn
          (whitespace-mode 1)
          (setq my-prev-whitespace-mode nil))))
  (advice-add 'company-pseudo-tooltip-unhide :before #'pre-popup-draw)
  (advice-add 'company-pseudo-tooltip-hide :after #'post-popup-draw)

  (defun nasy:local-push-company-backend (backend)
    "Add BACKEND to a buffer-local version of `company-backends'."
    (make-local-variable 'company-backends)
    (push backend company-backends))

  (diminish 'company-mode "CMP"))

(use-package company-try-hard
  :defer t
  :straight t
  :bind (:map company-active-map
         ("C-z" . company-try-hard)))


(use-package company-quickhelp
  :defer t
  :after company
  :straight t
  :bind (:map company-active-map
              ("C-c h" . company-quickhelp-manual-begin))
  :hook ((after-init . company-quickhelp-mode)))


(use-package company-math
  :defer t
  :straight t)


(use-package company-flx
  :defer t
  :straight t
  :after company
  :hook ((after-init . (lambda () (company-flx-mode +1)))))


;; version control (I gave up SVN)
;;----------------------------------------------------------------------------


(use-package git-blamed
  :straight t)


(use-package gitignore-mode
  :straight t)


(use-package gitconfig-mode
  :straight t)


(use-package git-timemachine
  :defer t
  :straight t)


(use-package magit-todos
  :straight t)


(use-package magit
  :defer t
  :straight t
  :hook ((magit-popup-mode-hook . no-trailing-whitespace))
  :init (setq-default magit-diff-refine-hunk t)
  :bind (([(meta f12)] . magit-status)  ;; Hint: customize `magit-repository-directories' so that you can use C-u M-F12 to
         ("C-c g"      . magit-status)  ;; quickly open magit on any one of your projects.  -- purcell
         ("C-x M-g"    . magit-dispatch-popup)
         :map magit-status-mode-map
         ("C-M-<up>"   . magit-section-up)
         :map vc-prefix-map
         ("f"          . vc-git-grep))
  :config (with-eval-after-load 'magit-todos
            (magit-todos-mode))
  (when *is-a-mac* (add-hook 'magit-mode-hook (lambda () (local-unset-key [(meta h)])))))


(use-package git-commit
  :defer t
  :straight t
  :hook ((git-commit-mode . goto-address-mode)))


(use-package git-messenger
  :defer t
  :straight t
  :init (setq git-messenger:show-detail t)
  :bind (:map vc-prefix-map
         ("p" . git-messenger:popup-message)))


(use-package git-gutter
  :straight t
  :diminish
  :hook (after-init . global-git-gutter-mode)
  :bind (("C-x C-g" . git-gutter)
         ("C-x v =" . git-gutter:popup-hunk)
         ("C-x p"   . git-gutter:previous-hunk)
         ("C-x n"   . git-gutter:next-hunk))
 :init (setq git-gutter:visual-line t
             git-gutter:disabled-modes '(asm-mode image-mode)
             git-gutter:modified-sign "■"
             git-gutter:added-sign "●"
             git-gutter:deleted-sign "✘"))


;; anzu
;;----------------------------------------------------------------------------

(use-package anzu
  :defer t
  :straight t
  :hook ((after-init . global-anzu-mode))
  :bind ([remap query-replace] . anzu-query-replace-regexp))


;; outline-magic
;;----------------------------------------------------------------------------

(use-package outline-magic
  :defer t
  :straight t
  :preface
  ;; https://www.emacswiki.org/emacs/python-magic.el
  (defun py-outline-level ()
    (let (buffer-invisibility-spec)
      (save-excursion
        (skip-chars-forward "    ")
        (current-column))))

  (defun python-outline-hook ()
    (setq outline-regexp "[ \t]+\\(class\\|def\\|if\\|elif\\|else\\|while\\|for\\|try\\|except\\|with\\) ")
    (setq outline-level 'py-outline-level)
    (outline-minor-mode t)
    (hide-body))

  :bind (:map outline-minor-mode-map
              ("<C-tab>" . outline-cycle))
  :hook ((python-mode . python-outline-hook))
  :diminish outline-minor-mode)


;; htmlize
;;----------------------------------------------------------------------------

(use-package htmlize
  :defer t
  :straight t)


;; projectile
;;----------------------------------------------------------------------------

(use-package projectile
  :defer t
  :straight t
  :diminish
  :bind (("C-c TAB" . projectile-find-other-file)
         ;; ("M-?" . counsel-search-project)
	 )
  :bind-keymap ("C-c C-p" . projectile-command-map)
  :hook ((after-init . projectile-global-mode))
  :init (setq projectile-require-project-root nil)
  :config (setq projectile-project-root-files-top-down-recurring
                (append '("compile_commands.json"
                          ".cquery")
                        projectile-project-root-files-top-down-recurring)))


;; helm settings
;;----------------------------------------------------------------------------

(use-package helm
   :defer t
   :straight t
   :diminish helm-mode
   :bind (("M-x"       . helm-M-x)
	  ("C-o"       . helm-occur)
	  ("<f1> SPC"  . helm-all-mark-rings) ; I modified the keybinding
	  ("M-y"       . helm-show-kill-ring)
	  ("C-x c x"   . helm-register)    ; C-x r SPC and C-x r j
	  ("C-x c g"   . helm-google-suggest)
	  ("C-x c M-:" . helm-eval-expression-with-eldoc)
	  ("C-x C-f"   . helm-find-files)
	  ("C-x b"     . helm-mini)      ; *<major-mode> or /<dir> or !/<dir-not-desired> or @<regexp>
	  :map helm-map
	  ("<tab>" . helm-execute-persistent-action) ; rebind tab to run persistent action
	  ("C-i"   . helm-execute-persistent-action) ; make TAB works in terminal
	  ("C-z"   . helm-select-action) ; list actions using C-z
	  :map shell-mode-map
	  ("C-c C-l" . helm-comint-input-ring) ; in shell mode
	  :map minibuffer-local-map
	  ("C-c C-l" . helm-minibuffer-history))
   :hook ((after-init . (lambda () (helm-mode 1)))
          (after-init . (lambda () (helm-autoresize-mode 1))))
   :init
   (require 'helm-config)

   (setq helm-M-x-fuzzy-match        t
	 helm-buffers-fuzzy-matching t
	 helm-recentf-fuzzy-match    t
	 helm-imenu-fuzzy-match      t
	 helm-locate-fuzzy-match     t
	 helm-apropos-fuzzy-match    t
	 helm-lisp-fuzzy-completion  t)

   (when (executable-find "curl")
     (setq helm-google-suggest-use-curl-p t))

   (setq helm-split-window-in-side-p           t ; open helm buffer inside current window, not occupy whole other window
	 helm-move-to-line-cycle-in-source     t ; move to end or beginning of source when reaching top or bottom of source.
	 helm-ff-search-library-in-sexp        t ; search for library in `require' and `declare-function' sexp.
	 helm-scroll-amount                    8 ; scroll 8 lines other window using M-<next>/M-<prior>
	 helm-ff-file-name-history-use-recentf t
	 helm-echo-input-in-header-line        t)

   :config
   (add-to-list 'helm-sources-using-default-as-input 'helm-source-man-pages))


(use-package helm-org
  :defer
  :config
  (cl-defun helm-org-headings-in-buffer ()
    (interactive)
    (helm :sources (helm-source-org-headings-for-files
                    (list (projectile-completing-read
                           "File to look at headings from: "
                           (projectile-all-project-files))))
          :candidate-number-limit 99999
          :buffer "*helm org inbuffer*")))


(use-package helm-eshell
  :after helm
  :bind (:map eshell-mode-map
              ("C-c C-l" . helm-eshell-history)))


(use-package helm-descbinds
  :straight t
  :after helm
  :hook ((after-init . helm-descbinds-mode)))


(use-package helm-projectile
  :straight t
  :hook ((after-init . helm-projectile-on))
  :init
  (setq projectile-completion-system 'helm))


(use-package helm-ag
  :straight t
  :init (setq helm-ag-fuzzy-match t
              helm-ag-use-grep-ignore-list t
              helm-ag-use-agignore t))


(use-package helm-dash
  :straight t
  :init (setq helm-dash-docsets-path "~/.docsets"))


(use-package helm-swoop
  :straight t
  :bind (("C-s" . helm-swoop))
  :init (setq helm-swoop-move-to-line-cycle   t
              helm-swoop-use-line-number-face t
              helm-swoop-use-fuzzy-match      t))


(use-package helm-ls-git
  :straight t
  :bind (("C-<f6>"   . helm-ls-git-ls)
         ("C-x C-g"  . helm-ls-git-ls)
         ("C-x C-d"  . helm-browse-project)))

;; Treemacs
;;----------------------------------------------------------------------------

(use-package treemacs
  :defer t
  :straight t
  :init
  (with-eval-after-load 'winum
    (define-key winum-keymap (kbd "M-0") #'treemacs-select-window))
  :config
  (progn
    (setq treemacs-collapse-dirs              (if (executable-find "python3") 3 0)
          treemacs-deferred-git-apply-delay   0.5
          treemacs-display-in-side-window     t
          treemacs-file-event-delay           5000
          treemacs-file-follow-delay          0.2
          treemacs-follow-after-init          t
          treemacs-follow-recenter-distance   0.1
          treemacs-goto-tag-strategy          'refetch-index
          treemacs-indentation                2
          treemacs-indentation-string         " "
          treemacs-is-never-other-window      nil
          treemacs-no-png-images              nil
          treemacs-project-follow-cleanup     nil
          treemacs-persist-file               (expand-file-name ".cache/treemacs-persist" user-emacs-directory)
          treemacs-recenter-after-file-follow nil
          treemacs-recenter-after-tag-follow  nil
          treemacs-show-hidden-files          t
          treemacs-silent-filewatch           nil
          treemacs-silent-refresh             nil
          treemacs-sorting                    'alphabetic-desc
          treemacs-space-between-root-nodes   t
          treemacs-tag-follow-cleanup         t
          treemacs-tag-follow-delay           1.5
          treemacs-width                      35)

    ;; The default width and height of the icons is 22 pixels. If you are
    ;; using a Hi-DPI display, uncomment this to double the icon size.
    (treemacs-resize-icons 44)

    (treemacs-follow-mode t)
    (treemacs-filewatch-mode t)
    (treemacs-fringe-indicator-mode t)
    (pcase (cons (not (null (executable-find "git")))
                 (not (null (executable-find "python3"))))
      (`(t . t)
       (treemacs-git-mode 'extended))
      (`(t . _)
       (treemacs-git-mode 'simple))))
  :bind
  (:map global-map
        ("M-0"       . treemacs-select-window)
        ("C-x t 1"   . treemacs-delete-other-windows)
        ("C-x t t"   . treemacs)
        ("C-x t B"   . treemacs-bookmark)
        ("C-x t C-t" . treemacs-find-file)
        ("C-x t M-t" . treemacs-find-tag)))


(use-package treemacs-projectile
  :after treemacs projectile
  :straight t)


;; auto insert
;;----------------------------------------------------------------------------

(use-package autoinsert
  :init
  (define-auto-insert
    '("\\.py" . "Python Language")
    '("Python Language"
      "#!/usr/bin/env python3\n"
      "# -*- coding: utf-8 -*-\n"
      "\"\"\"\n"
      "Life's pathetic, have fun (\"▔□▔)/hi~♡ Nasy.\n\n"
      "Excited without bugs::\n\n"
      "    |             *         *\n"
      "    |                  .                .\n"
      "    |           .\n"
      "    |     *                      ,\n"
      "    |                   .\n"
      "    |\n"
      "    |                               *\n"
      "    |          |\\___/|\n"
      "    |          )    -(             .              ·\n"
      "    |         =\\ -   /=\n"
      "    |           )===(       *\n"
      "    |          /   - \\\n"
      "    |          |-    |\n"
      "    |         /   -   \\     0.|.0\n"
      "    |  NASY___\\__( (__/_____(\\=/)__+1s____________\n"
      "    |  ______|____) )______|______|______|______|_\n"
      "    |  ___|______( (____|______|______|______|____\n"
      "    |  ______|____\\_|______|______|______|______|_\n"
      "    |  ___|______|______|______|______|______|____\n"
      "    |  ______|______|______|______|______|______|_\n"
      "    |  ___|______|______|______|______|______|____\n\n"
      "author   : Nasy https://nasy.moe\n"
      "date     : " (format-time-string "%b %e, %Y") \n
      "email    : Nasy <nasyxx+python@gmail.com>" \n
      "filename : " (file-name-nondirectory (buffer-file-name)) \n
      "project  : " (file-name-nondirectory (directory-file-name (projectile-project-root))) \n
      "license  : GPL-3.0+\n\n"
      "There are more things in heaven and earth, Horatio, than are dreamt.\n"
      " --  From \"Hamlet\"\n"
      "\"\"\"\n"))

  (define-auto-insert
    '("\\.hs" . "Haskell Language")
    '("Haskell Language"
      "{-\n"
      " Excited without bugs, have fun (\"▔□▔)/hi~♡ Nasy.\n"
      " ------------------------------------------------\n"
      " |             *         *\n"
      " |                  .                .\n"
      " |           .\n"
      " |     *                      ,\n"
      " |                   .\n"
      " |\n"
      " |                               *\n"
      " |          |\\___/|\n"
      " |          )    -(             .              ·\n"
      " |         =\\ -   /=\n"
      " |           )===(       *\n"
      " |          /   - \\\n"
      " |          |-    |\n"
      " |         /   -   \\     0.|.0\n"
      " |  NASY___\\__( (__/_____(\\=/)__+1s____________\n"
      " |  ______|____) )______|______|______|______|_\n"
      " |  ___|______( (____|______|______|______|____\n"
      " |  ______|____\\_|______|______|______|______|_\n"
      " |  ___|______|______|______|______|______|____\n"
      " |  ______|______|______|______|______|______|_\n"
      " |  ___|______|______|______|______|______|____\n\n"
      "There are more things in heaven and earth, Horatio, than are dreamt.\n"
      "   -- From \"Hamlet\"\n"
      "--------------------------------------------------------------------------------\n\n-}\n\n"
      "--------------------------------------------------------------------------------\n-- |\n"
      "-- Filename   : " (file-name-nondirectory (buffer-file-name)) \n
      "-- Project    : " (file-name-nondirectory (directory-file-name (projectile-project-root))) \n
      "-- Author     : Nasy\n"
      "-- License    : GPL-3.0+\n--\n"
      "-- Maintainer : Nasy <nasyxx+haskell@gmail.com>\n"
      "--\n--\n--\n--------------------------------------------------------------------------------\n")))


;; pretty
;;----------------------------------------------------------------------------

(use-package pretty-mode
  :demand t
  :straight t
  :hook (((prog-mode text-mode) . turn-on-pretty-mode)
         (after-init . global-prettify-symbols-mode)
         (python-mode . (lambda ()
                          (mapc (lambda (pair) (push pair prettify-symbols-alist))
                                '(;; Syntax
                                  ("def" .      #x2131)
                                  ;; ("not" .      #x2757)
                                  ("not" .      #xac)
                                  ("in" .       #x2208)
                                  ("not in" .   #x2209)
                                  ("return" .   #x27fc)
                                  ("yield" .    #x27fb)
                                  ("for" .      #x2200)
                                  ;; Extend Functions
                                  ("any" .      #x2754)
                                  ("all" .      #x2201)
                                  ("dict" .     #x1d507)
                                  ("list" .     #x2112)
                                  ("tuple" .    #x2a02)
                                  ("set" .      #x2126)
                                  ;; Base Types
                                  ("int" .      #x2124)
                                  ("float" .    #x211d)
                                  ("str" .      #x1d54a)
                                  ("True" .     #x1d54b)
                                  ("False" .    #x1d53d)
                                  ;; Extend Types
                                  ("Int" .      #x2124)
                                  ("Float" .    #x211d)
                                  ("String" .   #x1d54a)
                                  ;; Mypy
                                  ("Dict" .     #x1d507)
                                  ("List" .     #x2112)
                                  ("Tuple" .    #x2a02)
                                  ("Set" .      #x2126)
                                  ("Iterable" . #x1d50a)
                                  ("Any" .      #x2754)
                                  ("Union" .    #x22c3)))))
         (haskell-mode . (lambda ()
                          (mapc (lambda (pair) (push pair prettify-symbols-alist))
                                '(;; Syntax
                                  ("not" .      #x2757)
                                  ("in" .       #x2208)
                                  ("elem" .     #x2208)
                                  ("not in" .   #x2209)
                                  ("notElem" .  #x2209)
                                  ;; Types
                                  ("String" .   #x1d54a)
                                  ("Int" .      #x2124)
                                  ("Float" .    #x211d)
                                  ("True" .     #x1d54b)
                                  ("False" .    #x1d53d))))))
  :config
  (pretty-activate-groups
   '(:sub-and-superscripts :greek :arithmetic))

  (pretty-deactivate-groups
   '(:equality :ordering :ordering-double :ordering-triple
               :arrows :arrows-twoheaded :punctuation
               :logic :sets :arithmetic-double :arithmetic-triple)))


(use-package ipretty
  :defer t
  :straight t
  :hook ((after-init . ipretty-mode)))

;; https://github.com/tonsky/FiraCode/wiki/Emacs-instructions
;; This works when using emacs --daemon + emacsclient
(add-hook 'after-make-frame-functions (lambda (frame) (set-fontset-font t '(#Xe100 . #Xe16f) "Fira Code Symbol")))
;; This works when using emacs without server/client
(set-fontset-font t '(#Xe100 . #Xe16f) "Fira Code Symbol")
;; I haven't found one statement that makes both of the above situations work, so I use both for now

(defun pretty-fonts-set-fontsets (CODE-FONT-ALIST)
  "Utility to associate many unicode points with specified `CODE-FONT-ALIST'."
  (--each CODE-FONT-ALIST
    (-let (((font . codes) it))
      (--each codes
        (set-fontset-font nil `(,it . ,it) font)
        (set-fontset-font t `(,it . ,it) font)))))

(defun pretty-fonts--add-kwds (FONT-LOCK-ALIST)
  "Exploits `font-lock-add-keywords'(`FONT-LOCK-ALIST') to apply regex-unicode replacements."
  (font-lock-add-keywords
   nil (--map (-let (((rgx uni-point) it))
               `(,rgx (0 (progn
                           (compose-region
                            (match-beginning 1) (match-end 1)
                            ,(concat "\t" (list uni-point)))
                           nil))))
             FONT-LOCK-ALIST)))

(defmacro pretty-fonts-set-kwds (FONT-LOCK-HOOKS-ALIST)
  "Set regex-unicode replacements to many modes(`FONT-LOCK-HOOKS-ALIST')."
  `(--each ,FONT-LOCK-HOOKS-ALIST
     (-let (((font-locks . mode-hooks) it))
       (--each mode-hooks
         (add-hook it (-partial 'pretty-fonts--add-kwds
                                (symbol-value font-locks)))))))

(defconst pretty-fonts-fira-font
  '(;; OPERATORS
    ;; Pipes
    ("\\(<|\\)" #Xe14d) ("\\(<>\\)" #Xe15b) ("\\(<|>\\)" #Xe14e) ("\\(|>\\)" #Xe135)

    ;; Brackets
    ("\\(<\\*\\)" #Xe14b) ("\\(<\\*>\\)" #Xe14c) ("\\(\\*>\\)" #Xe104)
    ("\\(<\\$\\)" #Xe14f) ("\\(<\\$>\\)" #Xe150) ("\\(\\$>\\)" #Xe137)
    ("\\(<\\+\\)" #Xe155) ("\\(<\\+>\\)" #Xe156) ("\\(\\+>\\)" #Xe13a)

    ;; Equality
    ("\\(!=\\)" #Xe10e) ("\\(!==\\)"         #Xe10f) ("\\(=/=\\)" #Xe143)
    ("\\(/=\\)" #Xe12c) ("\\(/==\\)"         #Xe12d)
    ("\\(===\\)"#Xe13d) ("[^!/]\\(==\\)[^>]" #Xe13c)

    ;; Equality Special
    ("\\(||=\\)"  #Xe133) ("[^|]\\(|=\\)" #Xe134)
    ("\\(~=\\)"   #Xe166)
    ("\\(\\^=\\)" #Xe136)
    ("\\(=:=\\)"  #Xe13b)

    ;; Comparisons
    ("\\(<=\\)" #Xe141) ("\\(>=\\)" #Xe145)
    ("\\(</\\)" #Xe162) ("\\(</>\\)" #Xe163)

    ;; Shifts
    ("[^-=]\\(>>\\)" #Xe147) ("\\(>>>\\)" #Xe14a)
    ("[^-=]\\(<<\\)" #Xe15c) ("\\(<<<\\)" #Xe15f)

    ;; Dots
    ("\\(\\.-\\)"    #Xe122) ("\\(\\.=\\)" #Xe123)
    ("\\(\\.\\.<\\)" #Xe125)

    ;; Hashes
    ("\\(#{\\)"  #Xe119) ("\\(#(\\)"   #Xe11e) ("\\(#_\\)"   #Xe120)
    ("\\(#_(\\)" #Xe121) ("\\(#\\?\\)" #Xe11f) ("\\(#\\[\\)" #Xe11a)

    ;; REPEATED CHARACTERS
    ;; 2-Repeats
    ("\\(||\\)" #Xe132)
    ("\\(!!\\)" #Xe10d)
    ("\\(%%\\)" #Xe16a)
    ("\\(&&\\)" #Xe131)

    ;; 2+3-Repeats
    ("\\(##\\)"       #Xe11b) ("\\(###\\)"          #Xe11c) ("\\(####\\)" #Xe11d)
    ("\\(--\\)"       #Xe111) ("\\(---\\)"          #Xe112)
    ("\\({-\\)"       #Xe108) ("\\(-}\\)"           #Xe110)
    ("\\(\\\\\\\\\\)" #Xe106) ("\\(\\\\\\\\\\\\\\)" #Xe107)
    ("\\(\\.\\.\\)"   #Xe124) ("\\(\\.\\.\\.\\)"    #Xe126)
    ("\\(\\+\\+\\)"   #Xe138) ("\\(\\+\\+\\+\\)"    #Xe139)
    ("\\(//\\)"       #Xe12f) ("\\(///\\)"          #Xe130)
    ("\\(::\\)"       #Xe10a) ("\\(:::\\)"          #Xe10b)

    ;; ARROWS
    ;; Direct
    ("[^-]\\(->\\)" #Xe114) ("[^=]\\(=>\\)" #Xe13f)
    ("\\(<-\\)"     #Xe152)
    ("\\(-->\\)"    #Xe113) ("\\(->>\\)"    #Xe115)
    ("\\(==>\\)"    #Xe13e) ("\\(=>>\\)"    #Xe140)
    ("\\(<--\\)"    #Xe153) ("\\(<<-\\)"    #Xe15d)
    ("\\(<==\\)"    #Xe158) ("\\(<<=\\)"    #Xe15e)
    ("\\(<->\\)"    #Xe154) ("\\(<=>\\)"    #Xe159)

    ;; Branches
    ("\\(-<\\)"  #Xe116) ("\\(-<<\\)" #Xe117)
    ("\\(>-\\)"  #Xe144) ("\\(>>-\\)" #Xe148)
    ("\\(=<<\\)" #Xe142) ("\\(>>=\\)" #Xe149)
    ("\\(>=>\\)" #Xe146) ("\\(<=<\\)" #Xe15a)

    ;; Squiggly
    ("\\(<~\\)" #Xe160) ("\\(<~~\\)" #Xe161)
    ("\\(~>\\)" #Xe167) ("\\(~~>\\)" #Xe169)
    ("\\(-~\\)" #Xe118) ("\\(~-\\)"  #Xe165)

    ;; MISC
    ("\\(www\\)"                   #Xe100)
    ("\\(<!--\\)"                  #Xe151)
    ("\\(~@\\)"                    #Xe164)
    ("[^<]\\(~~\\)"                #Xe168)
    ("\\(\\?=\\)"                  #Xe127)
    ("[^=]\\(:=\\)"                #Xe10c)
    ("\\(/>\\)"                    #Xe12e)
    ("[^\\+<>]\\(\\+\\)[^\\+<>]"   #Xe16d)
    ("[^:=]\\(:\\)[^:=]"           #Xe16c)
    ("\\(<=\\)"                    #Xe157))
  "Fira font ligatures and their regexes.")

(pretty-fonts-set-kwds
 '((pretty-fonts-fira-font prog-mode-hook org-mode-hook)))

;; Languages
;;----------------------------------------------------------------------------

(use-package toml-mode
   :straight t)

;; lsp-mode

(use-package lsp-mode
  :demand t
  :straight (lsp-mode :host github :repo "nasyxx/lsp-mode"))

(use-package lsp-imenu
  :demand t
  :after lsp-mode
  :hook ((lsp-after-open . lsp-enable-imenu)))

(use-package lsp-ui
  :demand t
  :after lsp-mode
  :straight t
  :hook ((lsp-mode . lsp-ui-mode))
  :init
  (setq-default lsp-ui-doc-position 'at-point
		lsp-ui-doc-header nil
		lsp-ui-doc-include-signature nil
		lsp-ui-flycheck-enable nil
		lsp-ui-sideline-enable nil  ;; not really good at all.
		lsp-ui-sideline-update-mode 'point
		lsp-ui-sideline-delay 1
		lsp-ui-sideline-ignore-duplicate t
		lsp-ui-peek-always-show t)
  :config
  (define-key lsp-ui-mode-map [remap xref-find-definitions]
    #'lsp-ui-peek-find-definitions)
  (define-key lsp-ui-mode-map [remap xref-find-references]
    #'lsp-ui-peek-find-references))

(use-package company-lsp
  :defer t
  :after lsp-mode
  :straight t
  :init
  (setq company-lsp-async t
        company-lsp-enable-recompletion t
        company-lsp-enable-snippet nil
        company-lsp-cache-candidates nil))

;; eglot

(use-package eglot
  :disabled t
  :straight t)

;; C/C++/OBJC

(use-package lsp-clangd
  :straight t
  :hook (((c-mode c++-mode objc-mode) . lsp-clangd-c-enable)))


(use-package cquery
  :disabled t
  :commands lsp-cquery-enable
  :straight t
  :init (setq cquery-executable        "/usr/local/bin/cquery"
              cquery-extra-init-params '(:index (:comments 2) :cacheFormat "msgpack" :completion (:detailedLabel t)))
  :hook (((c-mode c++-mode) . lsp-cquery-enable)))


;; html

(use-package lsp-html
  :when (executable-find "html-languageserver")
  :straight t
  :hook ((html-mode . lsp-html-enable)))


;; python

(use-package python
  :commands python-mode
  :mode ("\\.py\\'" . python-mode)
  :interpreter (("python" . python-mode)
                ("python3" . python-mode))
  :preface
  (lsp-define-stdio-client lsp-python "python3"
                           #'projectile-project-root
                           (if use-pyenv
                               '("pyenv" "exec" "pyls")
                             '("pyls")))
  :hook ((python-mode . lsp-python-enable)
         (python-mode . (lambda () (setq lsp-ui-flycheck-enable nil
                                    lsp-ui-sideline-enable nil)))
         (python-mode . (lambda () (nasy:local-push-company-backend 'company-lsp)))
         (python-mode . (lambda () (nasy:local-push-company-backend '(company-dabbrev-code
                                                                      company-gtags
                                                                      company-etags
                                                                      company-keywords)))))
  :init (setq-default python-indent-offset 4
                      indent-tabs-mode nil
                      python-indent-guess-indent-offset nil
                      python-shell-completion-native-enable nil
                      python-shell-interpreter "ipython3"
                      python-shell-interpreter-args "-i --simple-prompt --classic"
                      py-ipython-command-args "-i --simple-prompt --classic"
                      py-python-command "python3"
                      flycheck-python-pycompile-executable "python3"
                      python-mode-modeline-display "Python"
                      python-skeleton-autoinsert t))


;; (use-package anaconda-mode
;;   :straight t
;;   :hook ((python-mode . anaconda-mode)
;;          (python-mode . anaconda-eldoc-mode)))

;; (use-package company-anaconda
;;   :straight t
;;   :hook ((python-mode . (lambda () (nasy:local-push-company-backend 'company-anaconda)))
;;          (python-mode . (lambda () (nasy:local-push-company-backend '(company-dabbrev-code
;;                                                                  company-gtags
;;                                                                  company-etags
;;                                                                  company-keywords))))))

;; (use-package elpy
;;   :demand t
;;   :after python
;;   :straight t
;;   :init (elpy-enable)
;;   (setq elpy-rpc-backend "jedi"
;;         elpy-rpc-python-command "python3")
;;   :hook ((python-mode . elpy-mode)
;;          (elpy-mode . (lambda () (setq elpy-modules (delq 'elpy-module-flymake elpy-modules))))))

;; disable due to lsp-mode
;; (use-package flycheck-pyflakes
;;   :after flycheck
;;   :straight t)


(use-package blacken
  :straight t
  :hook ((python-mode . blacken-mode)))


(use-package py-isort
  :straight t
  :hook (before-save . py-isort-before-save))


;; haskell

(use-package haskell-mode
  :straight t
  :preface
  (define-minor-mode stack-exec-path-mode
    "If this is a stack project, set `exec-path' to the path \"stack exec\" would use."
    nil
    :lighter ""
    :global nil
    (if stack-exec-path-mode
        (when (and (executable-find "stack")
                   (locate-dominating-file default-directory "stack.yaml"))
          (setq-local
           exec-path
           (seq-uniq
            (append (list (concat (string-trim-right (shell-command-to-string "stack path --local-install-root")) "/bin"))
                    (parse-colon-path
                     (replace-regexp-in-string "[\r\n]+\\'" ""
                                               (shell-command-to-string "stack path --bin-path"))))
            'string-equal)))
      (kill-local-variable 'exec-path)))

  (defvar lsp-haskell--config-options (make-hash-table))

  (defun lsp-haskell--set-configuration ()
    (lsp--set-configuration `(:languageServerHaskell ,lsp-haskell--config-options)))

  (defun lsp-haskell-set-config (name option)
    "Set a config option in the haskell lsp server."
    (puthash name option lsp-haskell--config-options))

  ;; The default settings here, if you want to change any about it, just do it.
  ;; For example:
  ;; (lsp-haskell-set-config "maxNumberOfProblems" 100)
  ;; (lsp-haskell-set-config "hlintOn" t)

  :hook ((haskell-mode . subword-mode)
         (haskell-mode . haskell-auto-insert-module-template)
         (haskell-mode . haskell-collapse-mode)
         (haskell-mode . haskell-indentation-mode)
         (haskell-mode . stack-exec-path-mode)
         (haskell-mode . (lambda () (setq-local tab-width 4)))
         (lsp-after-initialize . lsp-haskell--set-configuration))
  :bind (("C-x a a" . align)
         :map haskell-mode-map
         ("C-c h" . hoogle)
         ("C-o"   . open-line))
  :init (use-package lsp-haskell
          :straight t
          :hook ((haskell-mode   . lsp-haskell-enable)
                 (lsp-after-open . (lambda () (add-hook 'before-save-hook #'lsp-format-buffer nil t)))))

  (setq haskell-mode-stylish-haskell-path            "stylish-haskell"
        haskell-indentation-layout-offset            4
        haskell-process-suggest-haskell-docs-imports t
        haskell-process-suggest-hayoo-imports        t
        haskell-process-suggest-hoogle-imports       t
        haskell-process-suggest-remove-import-lines  t
        haskell-tags-on-save                         t)

  (add-to-list 'align-rules-list
             '(haskell-types
               (regexp . "\\(\\s-+\\)\\(::\\|∷\\)\\s-+")
               (modes quote (haskell-mode literate-haskell-mode))))
  (add-to-list 'align-rules-list
               '(haskell-assignment
                 (regexp . "\\(\\s-+\\)=\\s-+")
                 (modes quote (haskell-mode literate-haskell-mode))))
  (add-to-list 'align-rules-list
               '(haskell-arrows
                 (regexp . "\\(\\s-+\\)\\(->\\|→\\)\\s-+")
                 (modes quote (haskell-mode literate-haskell-mode))))
  (add-to-list 'align-rules-list
               '(haskell-left-arrows
                 (regexp . "\\(\\s-+\\)\\(<-\\|←\\)\\s-+")
                 (modes quote (haskell-mode literate-haskell-mode))))

  :config
  (push 'haskell-mode page-break-lines-modes)
  (defun haskell-mode-generate-tags (&optional and-then-find-this-tag)
    "Generate tags using Hasktags.  This is synchronous function.

If optional AND-THEN-FIND-THIS-TAG argument is present it is used
with function `xref-find-definitions' after new table was
generated."
    (interactive)
    (let* ((dir (haskell-cabal--find-tags-dir))
           (command (haskell-cabal--compose-hasktags-command dir)))
      (if (not command)
          (error "Unable to compose hasktags command")
        ;; I disabled the noisy shell command output.
        ;; The original is (shell-command command)
        (call-process-shell-command command nil "*Shell Command Output*" t)
        (haskell-mode-message-line "Tags generated.")
        (when and-then-find-this-tag
          (let ((tags-file-name dir))
            (xref-find-definitions and-then-find-this-tag)))))))


(use-package intero
  ;; :disabled t  ;; I'm not sure if it is a good idea to use intero with lsp-mode, but I like it.
  :straight t
  :after haskell-mode
  :hook (haskell-mode . (lambda () (intero-global-mode 1)))
  :config (define-key intero-mode-map (kbd "M-?") nil))




;; lisp

(use-package lisp-mode
  :preface
  (defun eval-last-sexp-or-region (prefix)
    "Eval region from BEG to END if active, otherwise the last sexp."
    (interactive "P")
    (if (and (mark) (use-region-p))
        (eval-region (min (point) (mark)) (max (point) (mark)))
      (pp-eval-last-sexp prefix)))
  :bind (("<remap> <eval-expression>" . pp-eval-expression)
         :map emacs-lisp-mode-map
         ("C-x C-e" . eval-last-sexp-or-region)))

(use-package highlight-quoted
  :defer t
  :straight t
  :hook ((emacs-lisp-mode . highlight-quoted-mode)))

;; markdown

(use-package markdown-mode
  :defer t
  :straight t
  :mode ("INSTALL\\'"
         "CONTRIBUTORS\\'"
         "LICENSE\\'"
         "README\\'"
         "\\.markdown\\'"
         "\\.md\\'"))


;; Org-mode
;;----------------------------------------------------------------------------

(use-package grab-mac-link
  :defer t
  :straight t)


(use-package org
  :straight org-plus-contrib
  :bind (("C-c l" . org-store-link)
         ("C-c a" . org-agenda)))


(use-package org-cliplink
  :defer t
  :straight t)


(use-package org-clock
  :after org
  :preface
  (defun show-org-clock-in-header-line ()
    "Show the clocked-in task in header line"
    (setq-default header-line-format '((" " org-mode-line-string ""))))

  (defun hide-org-clock-from-header-line ()
    "Hide the clocked-in task from header line"
    (setq-default header-line-format nil))
  :init
  (setq org-clock-persist t)
  (setq org-clock-in-resume t)
  ;; Save clock data and notes in the LOGBOOK drawer
  (setq org-clock-into-drawer t)
  ;; Save state changes in the LOGBOOK drawer
  (setq org-log-into-drawer t)
  ;; Removes clocked tasks with 0:00 duration
  (setq org-clock-out-remove-zero-time-clocks t)
  ;; Show clock sums as hours and minutes, not "n days" etc.
  (setq org-time-clocksum-format
        '(:hours "%d" :require-hours t :minutes ":%02d" :require-minutes t))
  :hook ((org-clock-in . show-org-clock-in-header-line)
         ((org-clock-out . org-clock-cancel) . hide-org-clock-from-header))
  :bind (:map org-clock-mode-line-map
             ([header-line mouse-2] . org-clock-goto)
             ([header-line mouse-1] . org-clock-menu))
  :config
  (when (and *is-a-mac* (file-directory-p "/Applications/org-clock-statusbar.app"))
    (add-hook 'org-clock-in-hook
              (lambda () (call-process "/usr/bin/osascript" nil 0 nil "-e"
                                  (concat "tell application \"org-clock-statusbar\" to clock in \""
                                          org-clock-current-task "\""))))
    (add-hook 'org-clock-out-hook
              (lambda () (call-process "/usr/bin/osascript" nil 0 nil "-e"
                                  "tell application \"org-clock-statusbar\" to clock out")))))

(use-package org-pomodoro
  :after org-agenda
  :init (setq org-pomodoro-keep-killed-pomodoro-time t)
  :bind (:map org-agenda-mode-map
              ("P" . org-pomodoro)))


(use-package org-wc
  :straight t)


(use-package ob-ditaa
  :after org
  :preface
  (defun grab-ditaa (url jar-name)
    "Download URL and extract JAR-NAME as `org-ditaa-jar-path'."
    (message "Grabbing " jar-name " for org.")
    (let ((zip-temp (make-temp-name "emacs-ditaa")))
      (unwind-protect
          (progn
            (when (executable-find "unzip")
              (url-copy-file url zip-temp)
              (shell-command (concat "unzip -p " (shell-quote-argument zip-temp)
                                     " " (shell-quote-argument jar-name) " > "
                                     (shell-quote-argument org-ditaa-jar-path)))))
        (when (file-exists-p zip-temp)
          (delete-file zip-temp)))))
  :config (unless (and (boundp 'org-ditaa-jar-path)
                       (file-exists-p org-ditaa-jar-path))
            (let ((jar-name "ditaa0_9.jar")
                  (url "http://jaist.dl.sourceforge.net/project/ditaa/ditaa/0.9/ditaa0_9.zip"))
              (setq org-ditaa-jar-path (expand-file-name jar-name (file-name-directory user-init-file)))
              (unless (file-exists-p org-ditaa-jar-path)
                (grab-ditaa url jar-name)))))


(use-package ob-plantuml
  :after org
  :config (let ((jar-name "plantuml.jar")
                (url "http://jaist.dl.sourceforge.net/project/plantuml/plantuml.jar"))
            (setq org-plantuml-jar-path (expand-file-name jar-name (file-name-directory user-init-file)))
            (unless (file-exists-p org-plantuml-jar-path)
              (url-copy-file url org-plantuml-jar-path))))


(use-package org-agenda
  :after org
  :init (setq-default org-agenda-clockreport-parameter-plist '(:link t :maxlevel 3))
  :hook ((org-agenda-mode . (lambda () (add-hook 'window-configuration-change-hook 'org-agenda-align-tags nil t)))
         (org-agenda-mode . hl-line-mode))
  :config (add-to-list 'org-agenda-after-show-hook 'org-show-entry)
  (let ((active-project-match "-INBOX/PROJECT"))

    (setq org-stuck-projects
          `(,active-project-match ("NEXT")))

    (setq org-agenda-compact-blocks t
          org-agenda-sticky t
          org-agenda-start-on-weekday nil
          org-agenda-span 'day
          org-agenda-include-diary nil
          org-agenda-sorting-strategy
          '((agenda habit-down time-up user-defined-up effort-up category-keep)
            (todo category-up effort-up)
            (tags category-up effort-up)
            (search category-up))
          org-agenda-window-setup 'current-window
          org-agenda-custom-commands
          `(("N" "Notes" tags "NOTE"
             ((org-agenda-overriding-header "Notes")
              (org-tags-match-list-sublevels t)))
            ("g" "GTD"
             ((agenda "" nil)
              (tags "INBOX"
                    ((org-agenda-overriding-header "Inbox")
                     (org-tags-match-list-sublevels nil)))
              (stuck ""
                     ((org-agenda-overriding-header "Stuck Projects")
                      (org-agenda-tags-todo-honor-ignore-options t)
                      (org-tags-match-list-sublevels t)
                      (org-agenda-todo-ignore-scheduled 'future)))
              (tags-todo "-INBOX"
                         ((org-agenda-overriding-header "Next Actions")
                          (org-agenda-tags-todo-honor-ignore-options t)
                          (org-agenda-todo-ignore-scheduled 'future)
                          (org-agenda-skip-function
                           '(lambda ()
                              (or (org-agenda-skip-subtree-if 'todo '("HOLD" "WAITING"))
                                  (org-agenda-skip-entry-if 'nottodo '("NEXT")))))
                          (org-tags-match-list-sublevels t)
                          (org-agenda-sorting-strategy
                           '(todo-state-down effort-up category-keep))))
              (tags-todo ,active-project-match
                         ((org-agenda-overriding-header "Projects")
                          (org-tags-match-list-sublevels t)
                          (org-agenda-sorting-strategy
                           '(category-keep))))
              (tags-todo "-INBOX/-NEXT"
                         ((org-agenda-overriding-header "Orphaned Tasks")
                          (org-agenda-tags-todo-honor-ignore-options t)
                          (org-agenda-todo-ignore-scheduled 'future)
                          (org-agenda-skip-function
                           '(lambda ()
                              (or (org-agenda-skip-subtree-if 'todo '("PROJECT" "HOLD" "WAITING" "DELEGATED"))
                                  (org-agenda-skip-subtree-if 'nottododo '("TODO")))))
                          (org-tags-match-list-sublevels t)
                          (org-agenda-sorting-strategy
                           '(category-keep))))
              (tags-todo "/WAITING"
                         ((org-agenda-overriding-header "Waiting")
                          (org-agenda-tags-todo-honor-ignore-options t)
                          (org-agenda-todo-ignore-scheduled 'future)
                          (org-agenda-sorting-strategy
                           '(category-keep))))
              (tags-todo "/DELEGATED"
                         ((org-agenda-overriding-header "Delegated")
                          (org-agenda-tags-todo-honor-ignore-options t)
                          (org-agenda-todo-ignore-scheduled 'future)
                          (org-agenda-sorting-strategy
                           '(category-keep))))
              (tags-todo "-INBOX"
                         ((org-agenda-overriding-header "On Hold")
                          (org-agenda-skip-function
                           '(lambda ()
                              (or (org-agenda-skip-subtree-if 'todo '("WAITING"))
                                  (org-agenda-skip-entry-if 'nottodo '("HOLD")))))
                          (org-tags-match-list-sublevels nil)
                          (org-agenda-sorting-strategy
                           '(category-keep))))))))))

(use-package org-bullets
  :after org
  :straight t
  :hook ((org-mode . (lambda () (org-bullets-mode 1)))))

(use-package org
  :preface
  (defadvice org-refile (after save-all-after-refile activate)
    "Save all org buffers after each refile operation."
    (org-save-all-org-buffers))

  ;; Exclude DONE state tasks from refile targets
  (defun verify-refile-target ()
    "Exclude todo keywords with a done state from refile targets."
    (not (member (nth 2 (org-heading-components)) org-done-keywords)))
  (setq org-refile-target-verify-function 'verify-refile-target)

  (defun org-refile-anywhere (&optional goto default-buffer rfloc msg)
    "A version of `org-refile' which allows refiling to any subtree."
    (interactive "P")
    (let ((org-refile-target-verify-function))
      (org-refile goto default-buffer rfloc msg)))

  (defun org-agenda-refile-anywhere (&optional goto rfloc no-update)
    "A version of `org-agenda-refile' which allows refiling to any subtree."
    (interactive "P")
    (let ((org-refile-target-verify-function))
      (org-agenda-refile goto rfloc no-update)))

  :bind (:map org-mode-map
              ("C-M-<up>" . org-up-element)
              ("M-h" . nil)
              ("C-c g" . org-mac-grab-link))
  :init
  (setq
   org-archive-mark-done nil
   org-archive-location "%s_archive::* Archive"
   org-archive-mark-done nil
   org-catch-invisible-edits 'show
   org-edit-timestamp-down-means-later t
   org-export-coding-system 'utf-8
   org-export-kill-product-buffer-when-displayed t
   org-fast-tag-selection-single-key 'expert
   org-hide-emphasis-markers t
   org-hide-leading-stars nil
   org-html-with-latex (quote mathjax)
   org-html-validation-link nil
   org-indent-mode-turns-on-hiding-stars nil
   org-support-shift-select t
   org-refile-use-cache nil
   org-refile-targets '((nil :maxlevel . 5) (org-agenda-files :maxlevel . 5))
   org-refile-use-outline-path t
   org-outline-path-complete-in-steps nil
   org-refile-allow-creating-parent-nodes 'confirm
   ;; to-do settings
   org-todo-keywords (quote ((sequence "TODO(t)" "NEXT(n)" "|" "DONE(d!/!)")
                             (sequence "PROJECT(p)" "|" "DONE(d!/!)" "CANCELLED(c@/!)")
                             (sequence "WAITING(w@/!)" "DELEGATED(e!)" "HOLD(h)" "|" "CANCELLED(c@/!)")))
   org-todo-repeat-to-state "NEXT"
   org-todo-keyword-faces (quote (("NEXT" :inherit warning)
                                  ("PROJECT" :inherit font-lock-string-face)))

   ;; org latex
   org-latex-compiler "lualatex"
   org-latex-default-packages-alist
   (quote
    (("AUTO" "inputenc" t
      ("pdflatex"))
     ("T1" "fontenc" t
      ("pdflatex"))
     ("" "graphicx" t nil)
     ("" "grffile" t nil)
     ("" "longtable" t nil)
     ("" "wrapfig" nil nil)
     ("" "rotating" nil nil)
     ("normalem" "ulem" t nil)
     ("" "amsmath" t nil)
     ("" "textcomp" t nil)
     ("" "amssymb" t nil)
     ("" "capt-of" nil nil)
     ("colorlinks,linkcolor=blue,anchorcolor=blue,citecolor=green,filecolor=black,urlcolor=blue"
      "hyperref" t nil)
     ("" "luatexja-fontspec" t nil)
     ("" "listings" t nil)))
   org-latex-default-table-environment "longtable"
   org-latex-listings t
   org-latex-listings-langs
   (quote
    ((emacs-lisp "Lisp")
     (lisp "Lisp")
     (clojure "Lisp")
     (c "C")
     (cc "C++")
     (fortran "fortran")
     (perl "Perl")
     (cperl "Perl")
     (Python "python")
     (python "Python")
     (ruby "Ruby")
     (html "HTML")
     (xml "XML")
     (tex "TeX")
     (latex "[LaTeX]TeX")
     (sh "bash")
     (shell-script "bash")
     (gnuplot "Gnuplot")
     (ocaml "Caml")
     (caml "Caml")
     (sql "SQL")
     (sqlite "sql")
     (makefile "make")
     (R "r")))
   org-latex-pdf-process
   (quote
    ("lualatex -shell-escape -interaction nonstopmode %f"
     "lualatex -shell-escape -interaction nonstopmode %f"))
   org-latex-tables-booktabs t
   org-level-color-stars-only nil
   org-list-indent-offset 2
   org-log-done t
   org-refile-use-outline-path t
   org-startup-indented t
   org-startup-folded (quote content)
   org-startup-truncated nil
   org-tags-column 80)
  :hook ((org-mode-hook . auto-fill-mode))
  :config
  (org-babel-do-load-languages
   'org-babel-load-languages
   `((R . t)
     (ditaa . t)
     (dot . t)
     (emacs-lisp . t)
     (gnuplot . t)
     (haskell . nil)
     (latex . t)
     (ledger . t)
     (ocaml . nil)
     (octave . t)
     (plantuml . t)
     (python . t)
     (ruby . t)
     (screen . nil)
     (,(if (locate-library "ob-sh") 'sh 'shell) . t)
     (sql . nil)
     (sqlite . t)))
  (setq luamagick
      '(luamagick
        :programs ("lualatex" "convert")
        :description "pdf > png"
        :message "you need to install lualatex and imagemagick."
        :use-xcolor t
        :image-input-type "pdf"
        :image-output-type "png"
        :image-size-adjust (1.0 . 1.0)
        :latex-compiler ("lualatex -interaction nonstopmode -output-directory %o %f")
        :image-converter ("convert -density %D -trim -antialias %f -quality 100 %O")))
  (add-to-list 'org-preview-latex-process-alist luamagick)
  (setq luasvg
      '(luasvg
        :programs ("lualatex" "dvisvgm")
        :description "dvi > svg"
        :message "you need to install lualatex and dvisvgm."
        :use-xcolor t
        :image-input-type "dvi"
        :image-output-type "svg"
        :image-size-adjust (1.7 . 1.5)
        :latex-compiler ("lualatex -interaction nonstopmode -output-format dvi -output-directory %o %f")
        :image-converter ("dvisvgm %f -n -b min -c %S -o %O")))
  (add-to-list 'org-preview-latex-process-alist luasvg)
  (setq org-preview-latex-default-process 'luasvg))


(use-package writeroom-mode
  :defer t
  :straight t
  :init
  (define-minor-mode prose-mode
    "Set up a buffer for prose editing.
This enables or modifies a number of settings so that the
experience of editing prose is a little more like that of a
typical word processor."
    nil " Prose" nil
    (if prose-mode
        (progn
          (when (fboundp 'writeroom-mode)
            (writeroom-mode 1))
          (setq truncate-lines nil)
          (setq word-wrap t)
          (setq cursor-type 'bar)
          (when (eq major-mode 'org)
            (kill-local-variable 'buffer-face-mode-face))
          (buffer-face-mode 1)
          ;;(delete-selection-mode 1)
          (set (make-local-variable 'blink-cursor-interval) 0.6)
          (set (make-local-variable 'show-trailing-whitespace) nil)
          (set (make-local-variable 'line-spacing) 0.2)
          (set (make-local-variable 'electric-pair-mode) nil)
          (ignore-errors (flyspell-mode 1))
          (visual-line-mode 1))
      (kill-local-variable 'truncate-lines)
      (kill-local-variable 'word-wrap)
      (kill-local-variable 'cursor-type)
      (kill-local-variable 'show-trailing-whitespace)
      (kill-local-variable 'line-spacing)
      (kill-local-variable 'electric-pair-mode)
      (buffer-face-mode -1)
      ;; (delete-selection-mode -1)
      (flyspell-mode -1)
      (visual-line-mode -1)
      (when (fboundp 'writeroom-mode)
        (writeroom-mode 0)))))


(use-package pdf-tools
  :straight t
  :config
  (setq-default pdf-view-display-size 'fit-width)
  (bind-keys :map pdf-view-mode-map
             ("\\" . hydra-pdftools/body)
             ("<s-spc>" .  pdf-view-scroll-down-or-next-page)
             ("g"  . pdf-view-first-page)
             ("G"  . pdf-view-last-page)
             ("l"  . image-forward-hscroll)
             ("h"  . image-backward-hscroll)
             ("j"  . pdf-view-next-page)
             ("k"  . pdf-view-previous-page)
             ("e"  . pdf-view-goto-page)
             ("u"  . pdf-view-revert-buffer)
             ("al" . pdf-annot-list-annotations)
             ("ad" . pdf-annot-delete)
             ("aa" . pdf-annot-attachment-dired)
             ("am" . pdf-annot-add-markup-annotation)
             ("at" . pdf-annot-add-text-annotation)
             ("y"  . pdf-view-kill-ring-save)
             ("i"  . pdf-misc-display-metadata)
             ("s"  . pdf-occur)
             ("b"  . pdf-view-set-slice-from-bounding-box)
             ("r"  . pdf-view-reset-slice)))

(use-package org-pdfview
  :after pdf-tools
  :straight t)

(use-package toc-org
  :defer t
  :straight t)


;; Themes and modeline
;;----------------------------------------------------------------------------

(use-package emojify
  :straight t
  :commands emojify-mode
  :hook ((after-init . global-emojify-mode))
  :init (setq emojify-emoji-styles '(unicode github)
              emojify-display-style 'unicode))


;; all the icons

(use-package all-the-icons
  :demand t
  :init (setq inhibit-compacting-font-caches t)
  :straight t)

;; Mode Line

(use-package mode-line-bell
  :demand t
  :straight t
  :hook ((after-init . mode-line-bell-mode)))


(use-package powerline
  :straight t)


(use-package nyan-mode
  :demand t
  :straight t
  :init (setq nyan-animate-nyancat t
              nyan-bar-length 16
              nyan-wavy-trail t)
  :config (nyan-mode 1))


(use-package spaceline-config
  :demand t
  :init
  (setq-default
   mode-line-format '("%e" (:eval (spaceline-ml-main)))
   powerline-default-separator 'contour
   powerline-gui-use-vcs-glyph t
   powerline-height 22
   spaceline-highlight-face-func 'spaceline-highlight-face-modified
   spaceline-workspace-numbers-unicode t
   spaceline-window-numbers-unicode t
   spaceline-separator-dir-left '(left . right)
   spaceline-separator-dir-right '(right . left)
   spaceline-flycheck-bullet "❀ %s")
  (spaceline-helm-mode 1)
  (spaceline-info-mode 1)
  :straight spaceline
  :config
  (spaceline-define-segment nasy:version-control
    "Version control information."
    (when vc-mode
      (let ((branch (mapconcat 'concat (cdr (split-string vc-mode "[:-]")) "-")))
        (powerline-raw
         (s-trim (concat "  "
                         branch
                         (when (buffer-file-name)
                           (pcase (vc-state (buffer-file-name))
                             (`up-to-date " ✓")
                             (`edited " ❓")
                             (`added " ➕")
                             (`unregistered " ■")
                             (`removed " ✘")
                             (`needs-merge " ↓")
                             (`needs-update " ↑")
                             (`ignored " ✦")
                             (_ " ⁇")))))))))

  (spaceline-define-segment nasy-time
    "Time"
    (format-time-string "%b %d, %Y - %H:%M ")
    :tight-right t)

  (spaceline-define-segment flycheck-status
    "An `all-the-icons' representaiton of `flycheck-status'"
    (let* ((text
            (pcase flycheck-last-status-change
              (`finished (if flycheck-current-errors
                             (let ((count (let-alist (flycheck-count-errors flycheck-current-errors)
                                            (+ (or .warning 0) (or .error 0)))))
                               (format "✖ %s Issue%s" count (if (eq 1 count) "" "s")))
                           "✔ No Issues"))
              (`running     "⟲ Running")
              (`no-checker  "⚠ No Checker")
              (`not-checked "✖ Disabled")
              (`errored     "⚠ Error")
              (`interrupted "⛔ Interrupted")
              (`suspicious  "")))
           (f (cond
               ((string-match "⚠" text) `(:height 0.9 :background ,(face-attribute 'spaceline-flycheck-warning :foreground)))
               ((string-match "✖ [0-9]" text) `(:height 0.9 :background ,(face-attribute 'spaceline-flycheck-error :foreground)))
               ((string-match "✖ Disabled" text) `(:height 0.9 :background ,(face-attribute 'font-lock-comment-face :foreground)))
               (t '(:height 0.9 :inherit)))))
      (propertize (format " %s " text)
                  'face f
                  'help-echo "Show Flycheck Errors"
                  'mouse-face '(:box 1)
                  'local-map (make-mode-line-mouse-map 'mouse-1 (lambda () (interactive) (flycheck-list-errors)))))
    :when active)

  (add-hook
   'after-init-hook
   (lambda () (spaceline-compile
           `(((buffer-modified major-mode buffer-size) :face highlight-face)
             (anzu)
             ((nasy:version-control projectile-root) :separator " in ")
             (buffer-id)
             ((flycheck-status (flycheck-error flycheck-warning flycheck-info)) :face powerline-active0 :when active)
             ((flycheck-status (flycheck-error flycheck-warning flycheck-info)) :face mode-line-inactive :when (not active))
             (selection-info :face powerline-active0 :when active)
             (nyan-cat :tight t :face mode-line-inactive))
           `((line-column :face powerline-active0 :when active)
             (line-column :when (not active))
             (which-function)
             (global :when active)
             ;; (minor-modes)
             (buffer-position
              hud)
             (nasy-time :face spaceline-modified :when active)
             (nasy-time :when (not active)))))))


;; custom file
;;----------------------------------------------------------------------------
(run-hooks 'nasy:config-before-hook)

(setq custom-file (expand-file-name "custom.el" user-emacs-directory))

(when (file-exists-p custom-file)
  (load custom-file))

(message "Start init hook in %.2fms"
         (benchmark-init/time-subtract-millis
          (current-time)
          emacs-start-init-time))

;;; init.el ends here
