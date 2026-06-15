# TODO: Update UserDashboard

- [x] Update `my-app/src/components/Dashboard/Dashboard.jsx`:
  - Move the "New Claim" button from the claims section header to the bottom of the claims section.
- [x] Update `my-app/src/components/Dashboard/Dashboard.css`:
  - Add CSS for `.new-claim-btn` to make it orange, matching the `.logout-btn` styling.
- [ ] Test the application to ensure the New Claim button works correctly and the form opens as expected.

# TODO: Update AdminDashboard

- [x] Update `my-app/src/pages/AdminDashboard.jsx`:
  - Add imports for ClaimsList, AIReport, History components.
  - Add state for activeView (default 'overview').
  - Add sidebar JSX with navigation buttons for Overview, Claims, AI Report, History, and Logout at bottom.
  - Update main content to conditionally render Overview (with boxes for Total Claims, Pending, Approved, Rejected), Claims (ClaimsList), AI Report (AIReport), History (History).
  - Remove logout from header, handle in sidebar.
- [x] Create `my-app/src/pages/AdminDashboard.css`:
  - Add CSS for sidebar layout, navigation buttons, overview boxes, responsive design.
- [ ] Test navigation between sections in AdminDashboard.
- [ ] Ensure layout is responsive and matches design.

# TODO: Enhance AdminLogin Page

- [x] Update `my-app/src/pages/AdminLogin.jsx`:
  - Enhance form styling with glassmorphism effect (backdrop blur, transparent background).
  - Update input fields with improved styling, focus animations, and glassmorphism.
  - Enhance submit button with gradient background and hover effects.
  - Add icons to input fields for better UX.
  - Improve header section with larger icon, better typography, and enhanced styling.
  - Update form shadow to use beautiful purple and pink colors instead of black.
- [x] Create `my-app/src/pages/AdminLogin.css`:
  - Add keyframe animations for floating elements and fade-in effects.
  - Include responsive design for mobile and tablet devices.
- [ ] Test the AdminLogin page to ensure all animations work correctly and the form is responsive.

# TODO: Enhance LoginSelection Page

- [x] Update `my-app/src/pages/LoginSelection.jsx`:
  - Change background to beautiful gradient (purple to pink).
  - Add floating background elements with animations.
  - Enhance card with glassmorphism effect and colored shadows.
  - Improve icon, typography, and button styling.
  - Add decorative background elements and animations.
