---
name: Premium Obsidian
colors:
  surface: '#0e1417'
  surface-dim: '#0e1417'
  surface-bright: '#333a3d'
  surface-container-lowest: '#090f12'
  surface-container-low: '#161d1f'
  surface-container: '#1a2123'
  surface-container-high: '#242b2e'
  surface-container-highest: '#2f3639'
  on-surface: '#dde3e7'
  on-surface-variant: '#bbc9cf'
  inverse-surface: '#dde3e7'
  inverse-on-surface: '#2b3134'
  outline: '#859399'
  outline-variant: '#3c494e'
  surface-tint: '#4cd6ff'
  primary: '#a4e6ff'
  on-primary: '#003543'
  primary-container: '#00d1ff'
  on-primary-container: '#00566a'
  inverse-primary: '#00677f'
  secondary: '#d0bcff'
  on-secondary: '#3c0091'
  secondary-container: '#571bc1'
  on-secondary-container: '#c4abff'
  tertiary: '#ffd59c'
  on-tertiary: '#442b00'
  tertiary-container: '#feb127'
  on-tertiary-container: '#6b4700'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#b7eaff'
  primary-fixed-dim: '#4cd6ff'
  on-primary-fixed: '#001f28'
  on-primary-fixed-variant: '#004e60'
  secondary-fixed: '#e9ddff'
  secondary-fixed-dim: '#d0bcff'
  on-secondary-fixed: '#23005c'
  on-secondary-fixed-variant: '#5516be'
  tertiary-fixed: '#ffddb1'
  tertiary-fixed-dim: '#ffba49'
  on-tertiary-fixed: '#291800'
  on-tertiary-fixed-variant: '#624000'
  background: '#0e1417'
  on-background: '#dde3e7'
  surface-variant: '#2f3639'
typography:
  headline-lg:
    fontFamily: Manrope
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
    letterSpacing: -0.02em
  headline-md:
    fontFamily: Manrope
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
    letterSpacing: -0.01em
  headline-sm:
    fontFamily: Manrope
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 28px
  body-lg:
    fontFamily: Manrope
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  body-md:
    fontFamily: Manrope
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  label-md:
    fontFamily: Manrope
    fontSize: 12px
    fontWeight: '600'
    lineHeight: 16px
    letterSpacing: 0.05em
  headline-lg-mobile:
    fontFamily: Manrope
    fontSize: 26px
    fontWeight: '700'
    lineHeight: 32px
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  grid-opacity: '0.05'
  margin-page: 2rem
  gutter: 1.5rem
  stack-sm: 0.5rem
  stack-md: 1rem
  stack-lg: 2rem
---

## Brand & Style
This design system is engineered for high-performance AI communication management. It employs a **Sophisticated Dark Mode** aesthetic that blends "Obsidian" depth with high-tech "Neon" accents. The personality is precise, authoritative, and intelligent. 

The visual style leverages **Glassmorphism** and **Tonal Layering** to create a multi-dimensional interface where AI-driven insights feel like they are floating above a vast, structured void. The target emotional response is one of total control and cognitive ease amidst high-volume data.

Key style principles:
- **Depth through Luminance:** Use subtle glows rather than heavy shadows to indicate hierarchy.
- **Cyber-Minimalism:** Eliminate unnecessary chrome; let the data and the AI-generated content define the structure.
- **Subtle Grid Geometry:** A faint structural grid underpins the layout to reinforce the feeling of a precision-engineered tool.

## Colors
The palette is rooted in the deep "Obsidian" spectrum to minimize eye strain during long-form monitoring and interaction.

- **Primary (Cyan):** Used for primary actions, active states, and essential navigation markers. It represents clarity and the "Atenda" brand essence.
- **Secondary (Violet):** Dedicated to "Intelligence" features—AI suggestions, automation triggers, and machine-learning insights.
- **Background & Surface:** The core foundation. `#07080d` acts as the deep canvas, while `#11141d` provides the elevation for cards, sidebars, and modular containers.
- **Accent (Orange):** Reserved strictly for critical semantic alerts, destructive actions, or high-priority billing notifications.
- **Status Colors:** Use Success (Emerald), Warning (Amber), and Error (Rose) sparingly, ensuring they are desaturated to maintain the premium feel.

## Typography
**Manrope** is the sole typeface, chosen for its modern, geometric construction that remains highly legible in dense data environments.

- **Headlines:** Use Bold or SemiBold weights with tighter letter-spacing for a "tech-editorial" look.
- **Labels:** Small caps or tracking increases are encouraged for secondary metadata (e.g., timestamps in "Conversas").
- **PT-BR Implementation:** Ensure all UI labels follow the provided terminology: *Visão Geral*, *Conversas*, *Automações*, *Ações*, *Templates WhatsApp*, *WhatsApp*, *Equipe*, *Configurações*, *Clientes*, and *Cobrança*.
- **Readability:** Maintain a high contrast ratio between the text (Neutral 100/200) and the dark surfaces.

## Layout & Spacing
The layout follows a **structured modular grid** with a reduced visual footprint. 

- **Background Grid:** A subtle background mesh or dot grid should be visible at **5% opacity** to provide a sense of scale without distracting from the content.
- **Side Navigation:** A fixed left-hand rail for the primary sections (*Visão Geral* through *Cobrança*). 
- **Content Areas:** Use fluid widths with a maximum container cap of 1440px for dashboard views. 
- **Responsive Behavior:** 
  - **Desktop:** 12-column grid.
  - **Tablet:** 8-column grid; sidebar collapses to icons.
  - **Mobile:** 4-column grid; bottom navigation for high-frequency items (*Conversas*, *Ações*).

## Elevation & Depth
Depth is created through **Luminance and Translucency** rather than traditional physical shadows.

- **Tier 0 (Background):** `#07080d`. The base layer containing the 5% opacity grid.
- **Tier 1 (Surface):** `#11141d`. Used for the main sidebar and card backgrounds.
- **Tier 2 (Floating):** Surfaces with a slight Cyan or Violet inner-glow (1px, 10% opacity) to indicate they are active or interactive.
- **Glassmorphism:** For overlays, modals, and dropdowns, use a backdrop filter (`blur(12px)`) combined with a semi-transparent version of the surface color (e.g., `rgba(17, 20, 29, 0.8)`).
- **Outlines:** Use 1px borders with `rgba(255, 255, 255, 0.08)` for inactive states, transitioning to the Primary Cyan for active focus.

## Shapes
The design system follows a **ROUND_FOUR** logic (standard 8px/0.5rem) to balance the technical sharpness of the color palette with a modern, approachable feel.

- **Small Components:** Checkboxes and small tags use `0.25rem` (Soft).
- **Standard UI:** Buttons, Input fields, and Cards use `0.5rem` (Rounded).
- **Large Containers:** Modals and large dashboard widgets use `1rem` (rounded-lg).
- **Interactive Pills:** Search bars and status badges may use full-round "pill" shapes where appropriate to distinguish them from structural blocks.

## Components
- **Buttons:** Primary buttons use a solid Cyan fill with dark text. Secondary (Intelligence) buttons use a Violet outline with a subtle inner glow. 
- **Conversas (Chat List):** Active chat items should be highlighted with a left-edge Cyan border (3px) and a subtle gradient fade.
- **Automações (Automation Cards):** Visual flow elements should use Violet connectors to signify AI-driven logic.
- **Input Fields:** Dark background (`#07080d`), 1px border. On focus, the border glows Cyan with a 4px outer blur at 20% opacity.
- **Chips/Badges:** Small, high-contrast labels for status (e.g., "Pendente", "Resolvido"). Use the secondary Violet color for any "AI-Processed" tags.
- **WhatsApp Templates:** Use a specialized card style that mimics the chat bubble structure but remains within the design system's technical aesthetic.