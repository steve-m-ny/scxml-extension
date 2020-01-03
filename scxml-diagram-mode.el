;;; scxml --- major mode for diagram interaction -*- lexical-binding: t -*-;

;;; Commentary:
;; This is the major mode for interacting with diagrams produced of scxml documents

;;; Code:
(require 'scxml-element)
(require 'scxml-draw)
(require 'scxml-geometry)
;; TODO - completely remove the dependency on artist.
(require 'artist)

(defvar scxml-diagram-mode--marked-element 'nil)
(make-variable-buffer-local 'scxml-diagram-mode--marked-element)
(defvar scxml-diagram-mode--last-click-pixel 'nil)
(make-variable-buffer-local 'scxml-diagram-mode--last-click-pixel)
(defvar scxml-diagram-mode--mark-element-catch 'nil
  "Override normal element marking functionality with this lambda.

If value is non-nil, this function will be executed instead
of the normal element marking routine.  Used for interactive selection of
elements.")
(make-variable-buffer-local 'scxml-diagram-mode--mark-element-catch)
(defvar scxml-diagram-mode--mouse-mode 'nil
  "Indicate what mouse mode you are in.
'viewport: - mode for panning/zooming the viewport
      nil: - normal mode, selection, editing, etc.")
(make-variable-buffer-local 'scxml-diagram-mode--mouse-mode)

(defvar scxml-diagram-mode-hook 'nil)

(defvar scxml-recording 'nil)
(defun scxml-start-recording ()
  (interactive)
  (setq scxml-recording (list 'start)))
(defun scxml-reset-recording ()
  (interactive)
  (setq scxml-recording nil))
(defmacro scxml-record (&rest recordable)
  `(when (and (called-interactively-p 'any) scxml-recording)
     (push (list ,@recordable) scxml-recording)))
(defun scxml-write-recording (buffer-name)
  "Write the recording out to a buffer."
  (interactive "sRecording Buffer Name: ")
  (let ((buffer (get-buffer-create buffer-name)))
    (switch-to-buffer buffer)
    (mapc (lambda (command-list)
            (insert (prin1-to-string command-list) "\n"))
          (reverse scxml-recording))))

;; `(when (called-interactively-p 'any)
  ;;    (push ,recordable scxml-recording)))
;; (defun scxml-record (&rest anything)
;;   (push anything scxml-recording))

;; note: how to make that mouse popup menus.
;;     (x-popup-menu t (list "Menu title" (list "" '("yes" . 'yes) '("no" . 'no))))
(defvar scxml-diagram-mode-map
  (let ((map (make-keymap)))
    (define-key map (kbd "C-SPC") 'scxml-diagram-mode--mark-at-point)
    (define-key map (kbd "<mouse-1>") 'scxml-diagram-mode--mouse-handler)
    (define-key map (kbd "<double-mouse-1>") 'scxml-diagram-mode--mouse-handler)
    (define-key map (kbd "<down-mouse-1>") 'scxml-diagram-mode--mouse-handler)
    (define-key map (kbd "<drag-mouse-1>") 'scxml-diagram-mode--mouse-handler)
    (define-key map (kbd "<mouse-3>") 'scxml-diagram-mode--mouse-handler)
    (define-key map (kbd "<double-mouse-3>") 'scxml-diagram-mode--mouse-handler)
    (define-key map (kbd "<down-mouse-3>") 'scxml-diagram-mode--mouse-handler)
    (define-key map (kbd "<drag-mouse-3>") 'scxml-diagram-mode--mouse-handler)

    ;; normally forward-sexp
    (define-key map (kbd "C-M-f") 'scxml-diagram-mode--next-element)
    ;; normally backward-sexp
    (define-key map (kbd "C-M-b") 'scxml-diagram-mode--prev-element);; mark-prev)
    ;; normally backwards-list and forwards-list
    (define-key map (kbd "C-M-n") 'scxml-diagram-mode--descend-element)
    (define-key map (kbd "C-M-p") 'scxml-diagram-mode--ascend-element)
    (define-key map (kbd "q") 'scxml-diagram-mode--cancel)
    (define-key map (kbd "r") 'scxml-diagram-mode--redraw)
    (define-key map (kbd "m") 'scxml-diagram-mode--toggle-mouse-mode)

    ;; drawing stuff.
    (define-key map (kbd "d") 'scxml-diagram-mode--toggle-edit-mode)
    (define-key map (kbd "s") 'scxml-diagram-mode--simplify)
    (define-key map (kbd "a") 'scxml-diagram-mode--automatic)
    (define-key map (kbd "M-f") 'scxml-diagram-mode--modify-right)
    (define-key map (kbd "M-b") 'scxml-diagram-mode--modify-left)
    (define-key map (kbd "M-p") 'scxml-diagram-mode--modify-up)
    (define-key map (kbd "M-n") 'scxml-diagram-mode--modify-down)

    ;; document modification
    (define-key map (kbd "C-d") 'scxml-diagram-mode--delete-marked)

    map)
  "Keymap for scxml-diagram major mode")
(defvar scxml-diagram-mode--debug 't)
(defun scxml-toggle-debug-mode ()
  "Flip debugging info on and off."
  (interactive)
  (setq scxml-diagram-mode--debug (not scxml-diagram-mode--debug))
  (message "SCXML debugr mode set to %s" (symbol-name scxml-diagram-mode--debug)))

(defun scxml-diagram-mode ()
  "Major mode for editing scxml diagrams"
  (interactive)
  (artist-mode-init)
  ;; (set-syntax-table wpdl-mode-syntax-table)
  (use-local-map scxml-diagram-mode-map)
  ;; (picture-mode)
  (setq major-mode 'scxml-diagram-mode)
  (setq mode-name "SCXML Diag")
  (setq-local truncate-lines 't)
  ;; (setq truncate-partial-width-windows ????) ; maybe not
  (run-hooks 'scxml-diagram-mode-hook))

(defun scxml-do-new (name)
  "Make a brand new drawing of an empty <scxml> with NAME."
  (interactive "s<scxml> name: ")
  ;; TODO - I don't think I need the IF on the line below.
  (let* ((root-element (if name (scxml-drawable-scxml :name name)
                         (scxml-drawable-scxml)))
         (canvas (scxml-canvas :x-min 0.0 :x-max 5.0
                               :y-min 0.0 :y-max 5.0));; (scxml-canvas--default));
         (viewport (scxml-build-viewport canvas))
         (buffer (scxml-draw--get-buffer name)))
    (scxml--init-buffer buffer)
    (let ((diagram (scxml-diagram :canvas canvas
                                  :viewport viewport
                                  :root root-element
                                  :display-element root-element
                                  :buffer buffer)))
      (scxml-draw diagram)
      (switch-to-buffer (scxml-buffer diagram)))))
(defun scxml-do-diagram (&optional drawing-buffer canvas)
  "Make a diagram of whatever buffer you're on."
  (interactive)
  (when (and drawing-buffer (not (bufferp drawing-buffer)))
    (error "Invalid buffer: %s" drawing-buffer))
  (let ((buffer (or drawing-buffer
                    (scxml-draw--get-buffer (format "%s" (current-buffer)))))
        (root-element (scxml-read-buffer)))
    (unless (object-of-class-p root-element 'scxml-scxml)
      (error "Unable to parse buffer as <scxml>"))
    (let* ((canvas (or canvas (scxml-canvas--default)))
           (viewport (scxml-build-viewport canvas)))
      (scxml--init-buffer buffer)
      (let ((diagram (scxml-diagram :canvas canvas
                                    :viewport viewport
                                    :root root-element
                                    :display-element root-element
                                    :buffer buffer)))
        (scxml-draw diagram)
        (switch-to-buffer (scxml-buffer diagram))))))
(defun scxml-do-link (&optional xml-buffer drawing-buffer canvas)
  "build a diagram based off the SCXML in xml-buffer and link them."
  (interactive)
  (when (not xml-buffer)
    (setq xml-buffer (current-buffer)))
  (unless (bufferp xml-buffer)
    (error "Invalid buffer: %s" xml-buffer))
  (when (and drawing-buffer (not (bufferp drawing-buffer)))
    (error "Invalid buffer: %s" drawing-buffer))
  (let ((buffer (or drawing-buffer (scxml-draw--get-buffer (format "%s"
                                                                   xml-buffer))))
        (root-element (scxml-read-buffer)))
    (unless (object-of-class-p root-element 'scxml-scxml)
      (error "Unable to parse buffer as <scxml>"))
    (split-window-right)
    (let* ((canvas (or canvas (scxml-canvas--default)))
           (viewport (scxml-build-viewport canvas)))
      (scxml--init-buffer buffer)
      (let ((diagram (scxml-diagram :canvas canvas
                                    :xml-buffer xml-buffer
                                    :viewport viewport
                                    :root root-element
                                    :display-element root-element
                                    :buffer buffer)))
        (scxml-draw diagram)
        (scxml-link-xml-buffer diagram)
        (switch-to-buffer (scxml-buffer diagram))))))

(defmacro scxml-save-excursion (&rest forms)
  "Execute FORMS and keep the cursor in the same place in the diagram."
  `(let ((position-sym (make-symbol "--pos-sym--"))
         (value-sym (make-symbol "--val-sym--")))
     (setf (symbol-value position-sym) (scxml-draw--get-pixel-at-point))
     (setf (symbol-value value-sym)
           (progn ,@forms))
     (scxml-draw--goto-pixel
      (let ((edit-idx (scxml-diagram-mode--edit-idx)))
        (if edit-idx
            (let* ((drawing (scxml-element-drawing scxml-diagram-mode--marked-element))
                   (edit-idx-point (scxml-edit-idx-point drawing edit-idx)))
              (scxml-get-pixel (scxml-diagram-mode--viewport)
                               edit-idx-point))
          (symbol-value position-sym))))
     (symbol-value value-sym)))

;; Helper functions
;; TODO - do I actually need these helper functions?
(defun scxml-diagram-mode--canvas ()
  "Grab the canvas"
  (scxml-diagram-canvas scxml-draw--diagram))
(defun scxml-diagram-mode--viewport ()
  "Grab the viewport"
  (scxml-diagram-viewport scxml-draw--diagram))
(defun scxml-diagram-mode--display-element ()
  "Grab the element to display"
  (scxml-diagram-display-element scxml-draw--diagram))
(defun scxml-diagram-mode--root ()
  "Grab the root of the display diagram"
  (scxml-diagram-root scxml-draw--diagram))
(defun scxml-diagram-mode--marked-drawing ()
  "Get marked element's drawing if it exists"
  (if scxml-diagram-mode--marked-element
      (scxml-element-drawing scxml-diagram-mode--marked-element)
    'nil))
(defun scxml-diagram-mode--edit-idx ()
  "Is the marked element in edit-mode?"
  (let ((element scxml-diagram-mode--marked-element))
    (and element (scxml--edit-idx element))))

;; User action responders
(defun scxml-diagram-mode--next-element ()
  "Head to the next thing"
  (interactive)
  (scxml-record 'scxml-diagram-mode--next-element)
  (when scxml-diagram-mode--marked-element
    (if (scxml-diagram-mode--edit-idx)
        (scxml-diagram-mode--edit-idx-next)
      (scxml-diagram-mode--mark-next))))
(defun scxml-diagram-mode--prev-element ()
  "Head to the previous thing"
  (interactive)
  (scxml-record 'scxml-diagram-mode--prev-element)
  (when scxml-diagram-mode--marked-element
    (if (scxml-diagram-mode--edit-idx)
        (scxml-diagram-mode--edit-idx-prev)
      (scxml-diagram-mode--mark-prev))))
(defun scxml-diagram-mode--descend-element ()
  "Head to the first child of the thing"
  (interactive)
  (scxml-record 'scxml-diagram-mode--descend-element)
  (when (and scxml-diagram-mode--marked-element
             (not (scxml-diagram-mode--edit-idx)))
    (scxml-diagram-mode--mark-first-child)))
(defun scxml-diagram-mode--ascend-element ()
  "Head to the parent of the thing."
  (interactive)
  (scxml-record 'scxml-diagram-mode--ascend-element)
  (when scxml-diagram-mode--marked-element
    (if (scxml-diagram-mode--edit-idx)
        (scxml-diagram-mode--disable-edit-mode)
      (scxml-diagram-mode--mark-parent))))
(defun scxml-diagram-mode--modify (move-vector)
  "Modify the selected drawing element by move-vector"
  (if (eq scxml-diagram-mode--mouse-mode 'viewport)
      ;; You're in viewport mode, modify the viewport.
      (let ((flipped (scxml-additive-inverse move-vector)))
        (scxml-diagram-mode--pan (scxml-x flipped) (scxml-y flipped)))
    ;; else, normal view/edit mode.
    (when scxml-diagram-mode--marked-element
      (unless (scxml-point-p move-vector)
        (error "Must supply an scxml-point as MOVE-VECTOR"))
      (scxml-save-excursion
       (scxml-diagram-mode--move move-vector)))))
(defun scxml-diagram-mode--modify-right ()
  "Modify rightward"
  (interactive)
  (scxml-record 'scxml-diagram-mode--modify-right)
  (scxml-diagram-mode--modify (scxml-point :x 1.0 :y 0.0)))
(defun scxml-diagram-mode--modify-left ()
  "Modify leftward"
  (interactive)
  (scxml-record 'scxml-diagram-mode--modify-left)
  (scxml-diagram-mode--modify (scxml-point :x -1.0 :y 0.0)))
(defun scxml-diagram-mode--modify-up ()
  "Modify upward"
  (interactive)
  (scxml-record 'scxml-diagram-mode--modify-up)
  (scxml-diagram-mode--modify (scxml-point :x 0.0 :y 1.0)))
(defun scxml-diagram-mode--modify-down ()
  "Modify downward"
  (interactive)
  (scxml-record 'scxml-diagram-mode--modify-down)
  (scxml-diagram-mode--modify (scxml-point :x 0.0 :y -1.0)))

(defun scxml-diagram-mode--redraw ()
  "Redraw the screen."
  (interactive)
  (scxml-record 'scxml-diagram-mode--redraw)
  (let ((start (float-time)))
    (scxml-draw scxml-draw--diagram)
    (let ((duration-ms (- (float-time) start)))
      (message "Render time: %s ms" duration-ms))
    (when scxml-diagram-mode--debug
      (scxml-diagram-mode--debug-barf))))

(defun scxml-diagram-mode--mouse-handler (event)
  "Handle any arbitrary non-movement mouse event"
  ;; TODO - Not sure if I'm approaching mouse handling properly.
  (interactive "e")
  ;; (message "Random mouse event: %s" event)
  (let ((current-window (first (second event))))
    (cl-flet ((pixel-from-event
               (event)
               ;; If you're not in the current window (where the event was started), do not produce a pixel.
               (when (eq (first (second event)) current-window)
                 (let ((col-row-cell (first (nthcdr 6 (second event)))))
                   (scxml-pixel :x (car col-row-cell)
                                :y (cdr col-row-cell))))))
      (let ((event-type (car event)))
        ;; mouse down handlers
        (when (or (eq event-type 'down-mouse-1)
                  (eq event-type 'down-mouse-2)
                  (eq event-type 'down-mouse-3))
          (mouse-set-point event)
          (let* ((start-pixel (pixel-from-event event))
                 (last-pixel start-pixel)
                 (event-count 0))
            (setq scxml-diagram-mode--last-click-pixel start-pixel)
            ;; (message "Mouse Down px: %s, %s"
            ;;          (scxml-print start-pixel)
            ;;          (scxml-print last-pixel))
            (track-mouse
              (while (and (setq event (read-event))
                          (mouse-movement-p event))
                ;; ok, you've started moving....
                (when (and (not (eq scxml-diagram-mode--mouse-mode 'viewport))
                           (eq 0 event-count))
                  (scxml-diagram-mode--mark-at-point)) ;mark whatever was where you first clicked, get ready to try and move it.
                (incf event-count)
                ;; (message "event count: %s" event-count)
                (let* ((current-pixel (pixel-from-event event)))
                  ;; Only process when the 'pixel' changes.  That's the smallest unit of distance a user can change something by
                  (when (and current-pixel ;pixel must be valid and exist (it won't exist if you leave the window)
                             (not (equal current-pixel last-pixel)))
                    (let* ((current-delta (scxml-subtract current-pixel last-pixel))
                           (total-delta (scxml-subtract current-pixel start-pixel))
                           (start (scxml-get-coord-centroid (scxml-diagram-mode--viewport) last-pixel))
                           (end (scxml-get-coord-centroid (scxml-diagram-mode--viewport) current-pixel))
                           (delta (scxml-subtract end start)))
                      ;; (message "delta pixel raw: %s" (scxml-subtract end start))
                      ;; (message "Mouse Event[%d]: start: %s, delta %s, t-delta %s, dir %s"
                      ;;          event-count
                      ;;          (scxml-print start-pixel)
                      ;;          (scxml-print current-delta)
                      ;;          (scxml-print total-delta)
                      ;;          (scxml--direction-name  (scxml-coarse-direction current-delta)))
                      ;; (message "delta: %s" (scxml-print delta))
                      ;; (message "type: %s" event-type)
                      (if (eq scxml-diagram-mode--mouse-mode 'viewport)
                          ;; viewport mode can pan or zoom
                          (cond ((eq event-type 'down-mouse-1)
                                 (scxml-diagram-mode--pan (* -1 (scxml-x delta))
                                                          (* -1 (scxml-y delta))))
                                ((eq event-type 'down-mouse-3)
                                 (scxml-diagram-mode--zoom (if (> (scxml-y delta) 0)
                                                               0.95
                                                             1.05)))
                                (t
                                 (error "Unknown mouse event type: %s" event-type)))
                        ;; default mouse mode can only modify.
                        (scxml-diagram-mode--modify delta)))
                    (setq last-pixel current-pixel)))))
            (setq event-type (car event))))

        ;; handle a click event (not a drag or down event)
        ;; (message "Handle Event: %s" event)
        (setq scxml-diagram-mode--last-click-pixel (pixel-from-event event))
        (if (eq scxml-diagram-mode--mouse-mode 'viewport)
            ;; viewport mode - currently don't do anything
            nil
          (progn
            (mouse-set-point event)
            (cond
             ((eq event-type 'mouse-1)
              (scxml-record 'goto-char (point))
              (scxml-record 'scxml-diagram-mode--mark-at-point)
              (scxml-diagram-mode--mark-at-point))
             ((eq event-type 'double-mouse-1)
              (scxml-record 'goto-char (point))
              (scxml-record 'scxml-diagram-mode--mark-at-point t)
              (scxml-diagram-mode--mark-at-point t)))))))))
(defun scxml-diagram-mode--toggle-mouse-mode ()
  (interactive)
  (scxml-record 'scxml-diagram-mode--toggle-mouse-mode)
  (setq scxml-diagram-mode--mouse-mode
        (if (eq scxml-diagram-mode--mouse-mode 'viewport)
            nil
          'viewport))
  (message "Toggle mouse mode to: %s"
           (or scxml-diagram-mode--mouse-mode 'default)))

(defun scxml-diagram-mode--pan-left (&optional delta)
  (interactive)
  (scxml-record 'scxml-diagram-mode--pan-left)
  (scxml-diagram-mode--pan (- (or delta 1)) 0))
(defun scxml-diagram-mode--pan-right (&optional delta)
  (interactive)
  (scxml-record 'scxml-diagram-mode--pan-right)
  (scxml-diagram-mode--pan (or delta 1) 0))
(defun scxml-diagram-mode--pan-up (&optional delta)
  (interactive)
  (scxml-record 'scxml-diagram-mode--pan-up)
  (scxml-diagram-mode--pan 0 (or delta 1)))
(defun scxml-diagram-mode--pan-down (&optional delta)
  (interactive)
  (scxml-record 'scxml-diagram-mode--pan-down)
  (scxml-diagram-mode--pan 0 (- (or delta 1))))
(defun scxml-diagram-mode--pan (delta-scratch-x delta-scratch-y)
  "Pan display by DELTA-SCRATCH-X, DELTA-SCRATCH-Y pixel in scratch coordinates."
  (oset scxml-draw--diagram
        viewport
        (scxml-pan-scratch (scxml-diagram-viewport scxml-draw--diagram)
                           (round delta-scratch-x)
                           (round delta-scratch-y)))
  (scxml-diagram-mode--redraw))

(defun scxml-diagram-mode--zoom-reset ()
  "Reset viewport to be exactly the display element canvas"
  (interactive)
  (scxml-record 'scxml-diagram-mode--zoom-reset)
  (oset scxml-draw--diagram
        viewport
        (scxml-build-viewport (scxml-diagram-mode--canvas)))
  (scxml-diagram-mode--redraw))
(defun scxml-diagram-mode--zoom-in (&optional ratio)
  "Zoom in by RATIO, defaulting to 10%"
  (interactive)
  (scxml-record 'scxml-diagram-mode--zoom-in)
  (scxml-diagram-mode--zoom (+ 1.0 (or ratio 0.1))))
(defun scxml-diagram-mode--zoom-out (&optional ratio)
  "Zoom out by RATIO, defaulting to 10%"
  (interactive)
  (scxml-record 'scxml-diagram-mode--zoom-out)
  (scxml-diagram-mode--zoom (- 1.0 (or ratio 0.1))))
(defun scxml-diagram-mode--zoom (alpha)
  "Zoom the viewport by alpha"
  (scxml-zoom (scxml-diagram-viewport scxml-draw--diagram) alpha)
  (scxml-diagram-mode--redraw))

(defun scxml-diagram-mode--unmark-all (&optional do-redraw)
  "Unmark all elements"
  (let ((element (scxml-diagram-mode--display-element)))
    (when element
      (scxml-visit
       element
       (lambda (e) (scxml--set-highlight e 'nil))
       (lambda (e) (object-of-class-p e 'scxml-drawable-element)))
      (when do-redraw (scxml-diagram-mode--redraw)))))
(defun scxml-diagram-mode--mark-next ()
  "whatever is marked, mark the next one at the same level"
  ;; TODO - refactor this, it's almost the same as mark-prev
  (interactive)
  (scxml-record 'scxml-diagram-mode--mark-next)
  (let* ((parent (scxml-parent scxml-diagram-mode--marked-element))
         (children (scxml-children parent))
         (current-element scxml-diagram-mode--marked-element)
         (next-element 'nil)
         (found-current 'nil))
    (mapc (lambda (child)
            (when (and (null next-element)
                       found-current)
              (setq next-element child))
            (when (eq current-element child)
              (setq found-current 't)))
          children)
    (when (null next-element)
      (setq next-element (car children)))
    (scxml-diagram-mode--mark-element next-element)))
(defun scxml-diagram-mode--mark-prev ()
  "Whatever is marked, mark the previous one at the same level"
  (interactive)
  (scxml-record 'scxml-diagram-mode--mark-prev)
  (let* ((parent (scxml-parent scxml-diagram-mode--marked-element))
         (children (scxml-children parent))
         (current-element scxml-diagram-mode--marked-element)
         (prev-element 'nil)
         (last-element 'nil))
    (mapc (lambda (child)
            (when (eq current-element child)
              (setq prev-element last-element))
            (setq last-element child))
          children)
    (when (null prev-element)
      (setq prev-element (nth (- (length children) 1) children)))
    (scxml-diagram-mode--mark-element prev-element)))
(defun scxml-diagram-mode--mark-first-child ()
  "Whatever is marked, mark the first child of it"
  (interactive)
  (scxml-record 'scxml-diagram-mode--mark-first-child)
  (let ((children (scxml-children scxml-diagram-mode--marked-element)))
    (if children
        (scxml-diagram-mode--mark-element (car children))
      (message "No children to mark"))))
(defun scxml-diagram-mode--mark-parent ()
  "Whatever is marked, mark the parent of it"
  (interactive)
  (scxml-record 'scxml-diagram-mode--mark-parent)
  (let* ((parent (scxml-parent scxml-diagram-mode--marked-element)))
    (when parent
      (scxml-diagram-mode--mark-element parent))))
(defun scxml-diagram-mode--mark-at-point (&optional double-mark)
  "Mark whatever your cursor is on.

When DOUBLE-MARK is non-nil mark sub elements of the element
marked.  DOUBLE-MARK should be though of as a double click.  Two
single mark events on the same thing should be roughly the same
as a single DOUBLE-MARK event.

If no elements are marked, attempt to mark thing at point.
If an element is already marked _and_ in edit-mode then see if
the user is attempting to mark an edit idx."
  (interactive)
  (scxml-record 'scxml-diagram-mode--mark-at-point)
  (let* ((pixel (scxml-draw--get-pixel-at-point))
         (viewport (scxml-diagram-mode--viewport))
         (drawing-coord (scxml-get-coord viewport pixel)))
    (block scxml--found
      ;; first, if a current element is marked and you're
      ;; double marking, prefer that element's edit idxs.
      (when (and (scxml-diagram-mode--edit-idx)
                 scxml-diagram-mode--marked-element)
        (cl-loop with edit-pts = (scxml-edit-idx-points
                                  (scxml-diagram-mode--marked-drawing))
                 for edit-pt in edit-pts
                 for edit-idx from 0 to (1- (length edit-pts))
                 if (scxml-contains drawing-coord edit-pt 'stacked)
                 do (progn
                      (scxml--set-edit-idx scxml-diagram-mode--marked-element edit-idx)
                      (return-from scxml--found))))
      (let ((element (scxml-diagram-mode--get-element drawing-coord)))
        (unless (eq scxml-diagram-mode--marked-element element)
          (scxml-diagram-mode--mark-element element t))

        ;; when using-double mark - bounce to edit idx marking.
        (when (or (scxml-diagram-mode--edit-idx)
                  double-mark)
          (let ((edit-pts (scxml-edit-idx-points (scxml-diagram-mode--marked-drawing))))
            (when edit-pts
              ;; mark the edit-idx you clicked on or whichever one you're closest to.
              (cl-loop with best-idx = 0
                       with best-distance = 999999
                       with best-pt = nil
                       for edit-pt in edit-pts
                       for edit-idx from 0 to (1- (length edit-pts))
                       if (scxml-contains drawing-coord edit-pt 'stacked)
                       do (progn
                            (scxml--set-edit-idx element edit-idx)
                            (setq pixel (scxml-get-pixel viewport edit-pt))
                            (cl-return))
                       else
                       do (let ((distance (scxml-distance (scxml-centroid drawing-coord)
                                                          edit-pt)))
                            (when (< distance best-distance)
                              (setq best-distance distance)
                              (setq best-pt edit-pt)
                              (setq best-idx edit-idx)))
                       finally (if double-mark
                                   (progn
                                     (scxml--set-edit-idx element best-idx)
                                     (setq pixel (scxml-get-pixel viewport best-pt)))
                                 (scxml--set-edit-idx element))))))))
    (scxml-diagram-mode--redraw)
    (scxml-draw--goto-pixel pixel)))
(defun scxml-diagram-mode--mark-element (element &optional do-not-redraw)
  "Mark the ELEMENT specified and redraw the display!"
  (if scxml-diagram-mode--mark-element-catch
      (prog1
          (funcall scxml-diagram-mode--mark-element-catch element)
        (setq scxml-diagram-mode--mark-element-catch nil))
    (scxml-diagram-mode--unmark-all)
    (setq scxml-diagram-mode--marked-element element)
    (scxml--set-highlight element 't)

    (when (not do-not-redraw)
      (scxml-diagram-mode--redraw))

    (when scxml-diagram-mode--debug
      (message "Marking %s" (scxml-print element)))))

(defun scxml-diagram-mode--move (move-vector)
  "Whatever edit-idx you're at (or not at), move it by MOVE-VECTOR."
  ;; TODO - should this be a cl-defmethod?
  (unless (scxml-point-p move-vector)
    (error "Must supply a scxml-point to specify move vector"))
  (scxml--modify-drawing-hint scxml-diagram-mode--marked-element
                              move-vector)
  (scxml-diagram-mode--apply-edit scxml-diagram-mode--marked-element)
  (scxml-diagram-mode--redraw))
(defun scxml-diagram-mode--simplify ()
  "Simplify the marked drawing if possible."
  (interactive)
  (scxml-record 'scxml-diagram-mode--simplify)
  (when scxml-diagram-mode--marked-element
    (scxml--simplify-drawing-hint scxml-diagram-mode--marked-element)
    (when (scxml-diagram-mode--edit-idx)
      (scxml--set-edit-idx scxml-diagram-mode--marked-element
                           (min (1- (scxml-num-edit-idxs scxml-diagram-mode--marked-element)))))
    (scxml-diagram-mode--redraw)))

(defun scxml-diagram-mode--automatic ()
  "Set the marked element to 'automatic' mode (not manually hinted)."
  (interactive)
  (scxml-record 'scxml-diagram-mode--automatic)
  (when scxml-diagram-mode--marked-element
    (scxml--set-edit-idx scxml-diagram-mode--marked-element 'nil)
    (scxml--set-hint scxml-diagram-mode--marked-element 'nil)
    (scxml--set-drawing-invalid scxml-diagram-mode--marked-element 't)
    (scxml-diagram-mode--redraw)))

(defun scxml-diagram-mode--move-to-edit-idx (drawing)
  "Move to the currently selected edit-idx of the DRAWING if it is set."
  (when (and drawing (scxml-drawing-edit-idx drawing))
    (let* ((point (scxml-edit-idx-point (scxml-diagram-mode--marked-drawing)
                                        (scxml-diagram-mode--edit-idx)))
           (pixel (scxml-get-pixel (scxml-diagram-mode--viewport) point)))
      (scxml-draw--goto-pixel pixel))))

(defun scxml-diagram-mode--disable-edit-mode ()
  ;; TODO - can this function be removed?
  "Disable edit mode, if you're in edit mode mark the parent."
  (when (null scxml-diagram-mode--marked-element)
    (error "Unable to un-edit drawing, no selection"))
  (scxml-save-excursion
   (scxml--set-edit-idx scxml-diagram-mode--marked-element 'nil)
   (scxml-diagram-mode--redraw)))
(defun scxml-diagram-mode--enable-edit-mode ()
  ;; TODO - can this function be removed?
  "If you have a marked drawing, enter edit mode."
  (when (null scxml-diagram-mode--marked-element)
    (error "Unable to edit drawing, no element marked"))
  (if (> (scxml-num-edit-idxs (scxml-diagram-mode--marked-drawing)) 0)
      (scxml-save-excursion
       (scxml--set-edit-idx scxml-diagram-mode--marked-element 0)
       (scxml-diagram-mode--redraw))
    (message "Unable to edit drawing without edit indices")))
(defun scxml-diagram-mode--toggle-edit-mode ()
  ;; TODO - can this function be removed?
  "Toggle edit idx flag of the drawing of the currently marked element."
  (interactive)
  (scxml-record 'scxml-diagram-mode--toggle-edit-mode)
  (if (scxml-diagram-mode--edit-idx)
      (scxml-diagram-mode--disable-edit-mode)
    (scxml-diagram-mode--enable-edit-mode)))

(defun scxml-diagram-mode--edit-idx-next ()
  ;; TODO - this is duplicated with the edit-idx-prev code.
  "Jump to the next edit idx point."
  (interactive)
  (scxml-record 'scxml-diagram-mode--edit-idx-next)
  (when (or (null scxml-diagram-mode--marked-element)
            (not (scxml--edit-idx scxml-diagram-mode--marked-element)))
    (error "Unable to move to next edit index, not in edit mode"))
  (scxml-diagram-mode--edit-idx-increment 1))
(defun scxml-diagram-mode--edit-idx-prev ()
  "Jump to the prev edit idx point."
  (interactive)
  (scxml-record 'scxml-diagram-mode--edit-idx-prev)
  (when (or (null scxml-diagram-mode--marked-element)
            (not (scxml--edit-idx scxml-diagram-mode--marked-element)))
    (error "Unable to move to next edit index, not in edit mode"))
  (scxml-diagram-mode--edit-idx-increment -1))
(defun scxml-diagram-mode--edit-idx-increment (increment)
  "Increment the edit-idx of the currently marked element by INCREMENT."
  (scxml-save-excursion
   (scxml--increment-edit-idx scxml-diagram-mode--marked-element increment)
   (scxml-diagram-mode--redraw)))

(defun scxml-diagram-mode--add-child-state (id)
  "Add a child <state> element to the marked element"
  (interactive "sNew <state> id: ")
  (let ((parent (or scxml-diagram-mode--marked-element
                    (scxml-diagram-mode--display-element))))
    (scxml-add-child parent (scxml-drawable-state :id id) t)
    (scxml-visit parent
                 (lambda (child)
                   (scxml--set-hint child nil)
                   (scxml--set-drawing-invalid child 't))
                 (lambda (child)
                   (object-of-class-p child 'scxml-drawable-element)))
    (scxml-diagram-mode--apply-edit parent t)
    (scxml-diagram-mode--redraw)))
(defun scxml-diagram-mode--add-child-transition ()
  (interactive)
  (message "Mark the element to be the transition target")
  (setq scxml-diagram-mode--mark-element-catch
        'scxml-diagram-mode--add-child-transition-to))
(defun scxml-diagram-mode--add-child-transition-to (target)
  "Add transition from currently marked element to TARGET.

If you're a human you probably want to call the interactive scxml-diagram-mode--add-child-transition."
  (when (not (object-of-class-p target 'scxml-element))
    (error "Invalid target for transition."))
  (let ((parent scxml-diagram-mode--marked-element))
    ;; TODO - this seems unsafe, validate that the target can be the
    ;; the target of a transition
    (scxml-add-child parent (scxml-drawable-transition :target (scxml-element-id target)))
    (scxml--set-drawing-invalid target 't)
    (scxml-visit parent
                 (lambda (child)
                   (scxml--set-drawing-invalid child 't))
                 (lambda (child)
                   (object-of-class-p child 'scxml-drawable-element)))
    (scxml-diagram-mode--redraw)
    (scxml-diagram-mode--apply-edit parent t)))

(defun scxml-diagram-mode--delete-marked ()
  "Delete the marked element, mark the parent."
  (interactive)
  (let ((parent (scxml-parent scxml-diagram-mode--marked-element)))
    (scxml-diagram-mode--delete scxml-diagram-mode--marked-element)
    (when parent
      (scxml-diagram-mode--mark-element parent))))
(defun scxml-diagram-mode--delete (element)
  "Delete ELEMENT from the document."
  ;; TODO - should this be a cl-defmethod?
  (let ((parent (scxml-parent element)))
    (when (null parent)
      (error "Unable to find parent of %s" (scxml-print element)))
    (scxml-make-orphan element)
    (scxml-visit parent
                 (lambda (sibling)
                   (scxml--set-drawing-invalid sibling 't))
                 (lambda (child)
                   (object-of-class-p child 'scxml-drawable-element)))
    (scxml-diagram-mode--apply-edit parent t)))

(defun scxml-diagram-mode--apply-edit (element &optional include-children)
  "Check ELEMENT in linked XML buffer and apply changes from the diagram."
  ;; going to need to inject tracking identifiers into the document and
  ;; slam them into my scxml-elements
  (scxml-xml-update-element scxml-draw--diagram element include-children))

(cl-defgeneric scxml-diagram-mode--get-element ((selection-rect scxml-rect))
  "Return the element inside the SELECTION-RECT."
  (scxml-find-element-selection scxml-draw--diagram selection-rect))

(defun scxml--map-plist (fn plist)
  "Map over the members of PLIST calling FN as FN(key, val)"
  (let ((current plist)
        (accumulator 'nil))
    (while (and current (cdr current))
      (push (funcall fn (car current) (cadr current)) accumulator)
      (setq current (cddr current)))
    accumulator))
(defun scxml-diagram-mode--debug-hint (element)
  (let ((hint (scxml--hint element)))
    (if hint
        (cond ((or (scxml-rect-p hint)
                   (scxml-arrow-hint-p hint)
                   (scxml-point-p hint))
               (scxml-print hint))
              ((scxml---drawing-nest-rect-hint-p hint)
               "it's a divided nest rect")
              ('t                       ;probably a plist :(
               (mapconcat 'identity
                          (scxml--map-plist (lambda (key val) (format "%s=%s" key val))
                                            hint)
                          "\n          ")))

      "nil")))
(defun scxml-diagram-mode--debug-barf ()
  "Barf out a ton of debug info at the bottom of the diagram"

  (scxml-draw--goto-pixel
   (scxml-pixel :x 0
                :y (round (+ 2 (scxml-required-pixel-height (scxml-diagram-mode--viewport))))))
  (delete-region (point) (point-max))
  (scxml-draw--goto-pixel
   (scxml-pixel :x 0
                :y (round(+ 3 (scxml-required-pixel-height (scxml-diagram-mode--viewport))))))

  (insert
   (format "Viewport: %s\n" (scxml-diagram-viewport scxml-draw--diagram))
   (format "mainCanv: %s\n" (scxml-diagram-mode--canvas))
   (format "linkBuff: %s\n" (scxml-xml-buffer scxml-draw--diagram)))

  (let ((marked scxml-diagram-mode--marked-element))
    (if marked
        (insert
         (format "lastClik: %s\n" (if scxml-diagram-mode--last-click-pixel
                                      (format "%s -> %s -> %s{%s} -> %s/%s"
                                              (scxml-print scxml-diagram-mode--last-click-pixel)
                                              (scxml-print (scxml-get-scratch-coord (scxml-diagram-mode--viewport)
                                                                                    scxml-diagram-mode--last-click-pixel))
                                              (scxml-print (scxml-get-coord (scxml-diagram-mode--viewport)
                                                                            scxml-diagram-mode--last-click-pixel))
                                              (scxml-print (scxml-get-scratch-coord (scxml-diagram-mode--viewport)
                                                                                    (scxml-BL (scxml-get-coord (scxml-diagram-mode--viewport)
                                                                                                               scxml-diagram-mode--last-click-pixel))))
                                              (scxml-print (scxml-get-pixel (scxml-diagram-mode--viewport)
                                                                            (scxml-BL (scxml-get-coord (scxml-diagram-mode--viewport)
                                                                                                       scxml-diagram-mode--last-click-pixel))))
                                              (scxml-print (scxml-get-pixel (scxml-diagram-mode--viewport)
                                                                            (scxml-centroid (scxml-get-coord (scxml-diagram-mode--viewport)
                                                                                                             scxml-diagram-mode--last-click-pixel)))))
                                    "none"))
         (format "Marked:   %s\n" (scxml-print marked))
         (format "-EditIdx: %s @ %s \n" (scxml-diagram-mode--edit-idx)
                 (when (scxml-diagram-mode--edit-idx)
                   (scxml-edit-idx-point (scxml-element-drawing marked) (scxml-diagram-mode--edit-idx))))
         (format "-Hint   : %s\n" (scxml-diagram-mode--debug-hint marked))
         (format "-GeoType: %s\n" (eieio-object-class (scxml-element-drawing marked)))
         (format "-Geometf: %s\n" (scxml-print (scxml-element-drawing marked))))
      (insert "No marked element\n\n")))
  (when scxml-recording
    (let ((step 0))
    (insert (mapconcat (lambda (x) (format "REC[%d]: %s" (incf step) x)) scxml-recording "\n")))))

(provide 'scxml-diagram-mode)
;;; scxml-diagram-mode.el ends here
