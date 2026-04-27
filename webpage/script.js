/**
 * SafeHer Premium 3D Web Experience
 * Core Logic: Lenis (Smooth Scroll), Three.js (Spatial BG), GSAP (ScrollTriggers & Animation)
 */

document.addEventListener("DOMContentLoaded", () => {
    // --- 1. SETUP LENIS SMOOTH SCROLL ---
    const lenis = new Lenis({
        duration: 1.2,
        easing: (t) => Math.min(1, 1.001 - Math.pow(2, -10 * t)), // https://www.desmos.com/calculator/brs54l4xou
        direction: 'vertical',
        gestureDirection: 'vertical',
        smooth: true,
        mouseMultiplier: 1,
        smoothTouch: false,
        touchMultiplier: 2,
        infinite: false,
    });

    lenis.on('scroll', ScrollTrigger.update);
    gsap.ticker.add((time) => { lenis.raf(time * 1000); });
    gsap.ticker.lagSmoothing(0);



    // --- 3. PRODUCT FRAME PRELOADING & CANVAS DRIVER ---
    const TOTAL_FRAMES = 40;
    const images = [];
    const productCanvas = document.getElementById('productCanvas');
    const ctx = productCanvas ? productCanvas.getContext('2d') : null;

    let preloadedCount = 0;

    function preloadFrames() {
        const loader = document.getElementById('loader');
        const fill = document.getElementById('loaderBarFill');
        const text = document.getElementById('loaderPercent');

        return new Promise((resolve) => {
            for (let i = 1; i <= TOTAL_FRAMES; i++) {
                const img = new Image();
                const num = String(i).padStart(3, '0');
                img.src = `frames/ezgif-frame-${num}.jpg`;
                
                img.onload = () => {
                    preloadedCount++;
                    updateLoader(preloadedCount, resolve);
                };
                img.onerror = () => {
                    preloadedCount++; // Count to avoid infinite wait
                    updateLoader(preloadedCount, resolve);
                };
                images.push(img);
            }
        });

        function updateLoader(count, resolve) {
            const p = Math.round((count / TOTAL_FRAMES) * 100);
            if (fill) fill.style.width = `${p}%`;
            if (text) text.innerText = `${p}%`;
            
            if (count === TOTAL_FRAMES) {
                setTimeout(() => {
                    if (loader) loader.classList.add('hidden');
                    initGSAP(); // Start animations after loading
                    resolve();
                }, 500);
            }
        }
    }

    function renderProductFrame(index) {
        if (!ctx || !images[index]) return;
        const img = images[index];
        
        ctx.clearRect(0, 0, productCanvas.width, productCanvas.height);
        
        // Calculate aspect ratio covering
        const imgAspect = img.width / img.height;
        const parentW = productCanvas.parentElement.clientWidth;
        const parentH = productCanvas.parentElement.clientHeight;
        const parentAspect = parentW / parentH;
        
        let drawW, drawH;
        if (parentAspect > imgAspect) {
            drawH = parentH * 0.85;
            drawW = drawH * imgAspect;
        } else {
            drawW = parentW * 0.85;
            drawH = drawW / imgAspect;
        }

        productCanvas.width = drawW;
        productCanvas.height = drawH;
        productCanvas.style.width = drawW + 'px';
        productCanvas.style.height = drawH + 'px';

        ctx.drawImage(img, 0, 0, drawW, drawH);
    }

    // --- 4. GSAP SCROLLTRIGGERS & ANIMATIONS ---
    function initGSAP() {
        gsap.registerPlugin(ScrollTrigger);

        // A. 3D Product Scrubbing
        const frameData = { frame: 0 };
        if (productCanvas) {
            // Initial render
            window.addEventListener('resize', () => renderProductFrame(Math.round(frameData.frame)));
            setTimeout(() => renderProductFrame(0), 100);

            const st = ScrollTrigger.create({
                trigger: "#product-3d",
                pin: true,
                start: "top top",
                end: "+=400%", // Depends on section height
                scrub: 0.5, // 0.5 sec smooth catch up
                onUpdate: (self) => {
                    const f = Math.min(TOTAL_FRAMES - 1, Math.floor(self.progress * TOTAL_FRAMES));
                    if (f !== Math.round(frameData.frame)) {
                        frameData.frame = f;
                        renderProductFrame(f);
                    }
                }
            });

            // Sync Overlays to the same ScrollTrigger progress
            const overlays = document.querySelectorAll('.overlay-text');
            overlays.forEach((overlay, i) => {
                // Approximate quarters of the total pin
                const startRange = (i / overlays.length);
                const endRange = ((i + 1) / overlays.length);

                gsap.to(overlay, {
                    scrollTrigger: {
                        trigger: "#product-3d",
                        start: `top+=${startRange * 400}% top`,
                        end: `top+=${endRange * 400}% top`,
                        scrub: true,
                    },
                    opacity: 1,
                    y: 0,
                    ease: "power2.out",
                    yoyo: true, // Fade out as we pass
                    repeat: 1
                });
            });
        }

        // B. Reusable Entrance Animations
        // General Reveal (Fade + slight up)
        gsap.utils.toArray('.gs-reveal').forEach(elem => {
            gsap.fromTo(elem, 
                { autoAlpha: 0, y: 30 }, 
                { duration: 1, autoAlpha: 1, y: 0, ease: "power3.out", scrollTrigger: { trigger: elem, start: "top 90%" } }
            );
        });

        // Simple Up
        gsap.utils.toArray('.gs-reveal-up').forEach(elem => {
            gsap.fromTo(elem, 
                { autoAlpha: 0, y: 50 }, 
                { duration: 1, autoAlpha: 1, y: 0, ease: "power3.out", scrollTrigger: { trigger: elem, start: "top 85%" } }
            );
        });

        // Simple Left
        gsap.utils.toArray('.gs-reveal-left').forEach(elem => {
            gsap.fromTo(elem, 
                { autoAlpha: 0, x: -50 }, 
                { duration: 1.2, autoAlpha: 1, x: 0, ease: "power3.out", scrollTrigger: { trigger: elem, start: "top 80%" } }
            );
        });

        // Staggered
        gsap.utils.toArray('.features-grid, .impact-grid, .faq-list, .footer-links-grid').forEach(grid => {
            const items = grid.querySelectorAll('.gs-stagger');
            if (items.length) {
                gsap.fromTo(items, 
                    { autoAlpha: 0, y: 30 }, 
                    { duration: 0.8, autoAlpha: 1, y: 0, stagger: 0.1, ease: "power2.out", scrollTrigger: { trigger: grid, start: "top 85%" } }
                );
            }
        });

        // Spec Counters + Stagger
        const specGrid = document.querySelector('.specs-grid');
        if (specGrid) {
            const specItems = specGrid.querySelectorAll('.gs-stagger-spec');
            ScrollTrigger.create({
                trigger: specGrid,
                start: "top 85%",
                onEnter: () => {
                    gsap.fromTo(specItems, 
                        { autoAlpha: 0, y: 30 }, 
                        { duration: 0.8, autoAlpha: 1, y: 0, stagger: 0.08, ease: "power2.out" }
                    );
                    
                    // Counter logic
                    specGrid.querySelectorAll('.counter').forEach(el => {
                        const target = parseFloat(el.getAttribute('data-target'));
                        gsap.to(el, {
                            innerHTML: target,
                            duration: 1.5,
                            ease: "power3.out",
                            snap: { innerHTML: 1 },
                            onUpdate: function() { el.innerHTML = Math.round(this.targets()[0].innerHTML); }
                        });
                    });
                },
                once: true
            });
        }

        // Details list (Inside view)
        const detailsContainer = document.querySelector('.inside-details');
        if (detailsContainer) {
            const details = detailsContainer.querySelectorAll('.gs-stagger-detail');
            gsap.fromTo(details, 
                { autoAlpha: 0, x: 30 }, 
                { duration: 0.8, autoAlpha: 1, x: 0, stagger: 0.15, ease: "power3.out", scrollTrigger: { trigger: detailsContainer, start: "top 80%" } }
            );
        }

        // Specific Pricing Card animation
        const mainPricing = document.getElementById('pricing-main');
        if (mainPricing) {
            gsap.fromTo(mainPricing, 
                { autoAlpha: 0, scale: 0.95, y: 40 },
                { duration: 1, autoAlpha: 1, scale: 1, y: 0, ease: "back.out(1.2)", scrollTrigger: { trigger: mainPricing, start: "top 85%" } }
            );
        }
    }

    // --- 5. MAGNETIC BUTTONS APP ---
    function setupMagneticButtons() {
        document.querySelectorAll('.magnetic-btn').forEach(btn => {
            btn.addEventListener('mousemove', (e) => {
                const rect = btn.getBoundingClientRect();
                const h = rect.width / 2;
                // calculate offset from center
                const x = e.clientX - rect.left - h;
                const y = e.clientY - rect.top - (rect.height / 2);

                gsap.to(btn, {
                    x: x * 0.3,
                    y: y * 0.3,
                    duration: 0.4,
                    ease: 'power2.out'
                });
                
                // Content subtle pull
                const children = btn.querySelectorAll('span, svg');
                if (children.length) {
                    gsap.to(children, {
                        x: x * 0.15,
                        y: y * 0.15,
                        duration: 0.4,
                        ease: 'power2.out'
                    });
                }
            });

            btn.addEventListener('mouseleave', () => {
                gsap.to(btn, { x: 0, y: 0, duration: 0.7, ease: 'elastic.out(1, 0.3)' });
                const children = btn.querySelectorAll('span, svg');
                if (children.length) {
                    gsap.to(children, { x: 0, y: 0, duration: 0.7, ease: 'elastic.out(1, 0.3)' });
                }
            });
        });
    }

    // --- 6. UTILITIES (Nav, FAQ, Smooth Anchors) ---
    function setupInteractivity() {
        // Navbar Scrolled State
        const navbar = document.getElementById('navbar');
        window.addEventListener('scroll', () => {
            if (window.scrollY > 80) navbar.classList.add('scrolled');
            else navbar.classList.remove('scrolled');
        }, { passive: true });

        // Mobile Menu Toggle
        const hamburger = document.getElementById('navHamburger');
        const mobileMenu = document.getElementById('mobileMenu');
        if (hamburger && mobileMenu) {
            const toggleMenu = () => {
                hamburger.classList.toggle('active');
                mobileMenu.classList.toggle('active');
                if (mobileMenu.classList.contains('active')) lenis.stop();
                else lenis.start();
            };
            hamburger.addEventListener('click', toggleMenu);
            document.querySelectorAll('.mobile-link, .mobile-cta').forEach(link => {
                link.addEventListener('click', () => {
                    hamburger.classList.remove('active');
                    mobileMenu.classList.remove('active');
                    lenis.start();
                });
            });
        }

        // FAQ Toggle
        document.querySelectorAll('.faq-question').forEach(btn => {
            btn.addEventListener('click', () => {
                const item = btn.closest('.faq-item');
                const isActive = item.classList.contains('active');
                document.querySelectorAll('.faq-item').forEach(fi => {
                    fi.classList.remove('active');
                    fi.querySelector('.faq-question').setAttribute('aria-expanded', 'false');
                });
                if (!isActive) {
                    item.classList.add('active');
                    btn.setAttribute('aria-expanded', 'true');
                }
            });
        });

        // Lenis anchor scrolling
        document.querySelectorAll('a[href^="#"]').forEach(anchor => {
            anchor.addEventListener('click', function(e) {
                e.preventDefault();
                const target = document.querySelector(this.getAttribute('href'));
                if (target) {
                    lenis.scrollTo(target, { offset: -80, duration: 1.2 });
                }
            });
        });
    }


    setupMagneticButtons();
    setupInteractivity();
    preloadFrames(); // Resolving preload initializes GSAP

});
