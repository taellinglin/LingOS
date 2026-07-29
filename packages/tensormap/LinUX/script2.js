const canvas = document.getElementById("gameCanvas");
const ctx = canvas.getContext("2d");

const SCREEN_WIDTH = 1920;
const SCREEN_HEIGHT = 1080;
const FONT_SIZE = 10;
const CELL_SIZE = 10;
const FPS = 240;

canvas.width = SCREEN_WIDTH;
canvas.height = SCREEN_HEIGHT;

const cols = Math.floor(SCREEN_WIDTH / CELL_SIZE);
const rows = Math.floor(SCREEN_HEIGHT / CELL_SIZE);
const halfCols = Math.floor(cols / 2);
const halfRows = Math.floor(rows / 2);

const RED = "rgb(255, 0, 0)";
const BLUE = "rgb(0, 0, 255)";
const GREEN = "rgb(255, 255, 255)";
const BLACK = "rgb(0, 0, 0)";


const GALAXY_RADIUS = 4096;
const GALAXY_SPIN_SPEED = 0.2;

const GALAXY_COUNT = 6;
const GALAXY_ARMS = 6;
const GALAXY_POINTS = 128;

let galaxies = Array.from({ length: GALAXY_COUNT }, () => ({
  x: Math.random() * SCREEN_WIDTH,
  y: Math.random() * SCREEN_HEIGHT,
  angle: 0,
  spin: (Math.random() < 0.5 ? -1 : 1) * 0.001,
  char: randomChar(),
  colorTime: Math.random() * 1
}));

function drawGalaxyChar(x, y, char, color) {
  ctx.fillStyle = color;
  ctx.font = `${FONT_SIZE}px o`;
  ctx.fillText(char, x, y);
}

let mouseX = 0;
let mouseY = 0;

// Mousemove event listener
canvas.addEventListener("mousemove", (event) => {
  mouseX = event.clientX;
  mouseY = event.clientY;
});

// Random char generators
function randomChar() {
  const letters = "abcdefghijklmnopqrstuvwxyz";
  return letters[Math.floor(Math.random() * letters.length)];
}

function randomMatrixChar() {
  const matrixSet = "123456789";
  return matrixSet[Math.floor(Math.random() * matrixSet.length)];
}

function randomColor() {
  return Math.random() > 0.5 ? RED : BLUE;
}

function randomCell() {
  return {
    char: randomChar(),
    color: randomColor(),
    alive: Math.random() > 0.5,
  };
}

// Quarter grid for Conway cells
let quarterGrid = Array.from({ length: halfRows }, () =>
  Array.from({ length: halfCols }, randomCell)
);

// Matrix rain layer
let rainGrid = Array.from({ length: cols }, () => ({
  x: Math.floor(Math.random() * cols),
  y: Math.floor(Math.random() * rows),
  dx: Math.random() > 0.5 ? 1 : -1,
  dy: Math.random() > 0.5 ? 1 : -1,
  speed: Math.random() * 0.05 + Math.random() * 0.05,
  char: randomMatrixChar(),
  isDiagonal: true,
  colorCycleTime: Math.random() * 1000,
}));

// Symmetric cell mirroring
function buildFullGrid() {
  const grid = [];
  for (let y = 0; y < rows; y++) {
    const row = [];
    for (let x = 0; x < cols; x++) {
      const sourceX = x < halfCols ? x : cols - x - 1;
      const sourceY = y < halfRows ? y : rows - y - 1;
      row.push({ ...quarterGrid[sourceY][sourceX] });
    }
    grid.push(row);
  }
  return grid;
}

let grid = buildFullGrid();

// Game of Life rules
function countAliveNeighbors(x, y) {
  let count = 0;
  for (let dy = -1; dy <= 1; dy++) {
    for (let dx = -1; dx <= 1; dx++) {
      if (dx === 0 && dy === 0) continue;
      const nx = (x + dx + cols) % cols;
      const ny = (y + dy + rows) % rows;
      if (grid[ny][nx].alive) count++;
    }
  }
  return count;
}

function updateQuarterGrid() {
  const newQuarter = quarterGrid.map(row => row.map(cell => ({ ...cell })));

  for (let y = 0; y < halfRows; y++) {
    for (let x = 0; x < halfCols; x++) {
      const cell = quarterGrid[y][x];
      const fullX = x;
      const fullY = y;
      const neighbors = countAliveNeighbors(fullX, fullY);

      if (cell.alive) {
        if (neighbors < 2 || neighbors > 3) {
          newQuarter[y][x].alive = false;
        }
      } else {
        if (neighbors === 3) {
          newQuarter[y][x].alive = true;
          newQuarter[y][x].char = randomChar();
          newQuarter[y][x].color = randomColor();
        }
      }

      if (Math.random() < 0.0005) {
        newQuarter[y][x].alive = !newQuarter[y][x].alive;
      }
    }
  }

  quarterGrid = newQuarter;
}
function updateNumberGrid() {
    const newRainGrid = rainGrid.map(rain => ({ ...rain }));
  
    for (let i = 0; i < rainGrid.length; i++) {
      const rain = rainGrid[i];
      let neighbors = 0;
  
      const positions = [
        [rain.x, rain.y],
        [cols - rain.x - 1, rain.y],
        [rain.x, rows - rain.y - 1],
        [cols - rain.x - 1, rows - rain.y - 1],
      ];
  
      positions.forEach(([px, py]) => {
        if (px >= 0 && px < cols && py >= 0 && py < rows) {
          neighbors++;
        }
      });
  
      // Slow down transition to diagonal state
      if (rain.isDiagonal) {
        // Game of Life-like logic, slow down transition
        if (neighbors < 2 || neighbors > 3) {
          if (rain.diagonalTransitionCounter > 5) {
            newRainGrid[i].isDiagonal = false;
          } else {
            newRainGrid[i].diagonalTransitionCounter++;
          }
        }
      } else {
        if (neighbors === 3 && rain.diagonalTransitionCounter <= 0) {
          newRainGrid[i].isDiagonal = true;
          newRainGrid[i].char = randomMatrixChar();
          newRainGrid[i].diagonalTransitionCounter = 0;
        }
      }
    }
  
    rainGrid = newRainGrid;
  }

  
  function updateRain() {
    const occupied = new Map();
  
    // Track occupied positions before move
    for (const rain of rainGrid) {
      const key = `${rain.x},${Math.floor(rain.y)}`;
      occupied.set(key, rain);
    }
  
    for (let i = 0; i < rainGrid.length; i++) {
      const rain = rainGrid[i];
  
      if (rain.isDiagonal) {
        // Slow down diagonal speed
        rain.x += rain.dx * 0.001;  // Very slow horizontal drift
        rain.y += rain.dy * 0.001;  // Very slow vertical drift
  
        // Wrap around edges
        rain.x = (rain.x + cols) % cols;
        rain.y = (rain.y + rows) % rows;
  
        const key = `${Math.floor(rain.x)},${Math.floor(rain.y)}`;
        if (occupied.has(key)) {
          // Bounce back
          rain.dx *= -1;
          rain.dy *= -1;
        }
      } else {
        // Slow normal vertical rain
        rain.y += rain.speed * 0.05;  // MUCH slower fall speed
  
        if (rain.y >= rows) {
          rain.y = 0;
          rain.char = randomMatrixChar();
        }
      }
  
      // Keep color cycling as-is
      rain.colorCycleTime += 5;
      const r = Math.floor(Math.sin(rain.colorCycleTime * 0.05) * 127 + 128);
      const g = Math.floor(Math.sin(rain.colorCycleTime * 0.05 + 2) * 127 + 128);
      const b = Math.floor(Math.sin(rain.colorCycleTime * 0.05 + 4) * 127 + 128);
      rain.color = `rgb(${r}, ${g}, ${b})`;
  
      // Mouse influence - dampen significantly
      const distanceToMouse = Math.sqrt(
        Math.pow(rain.x * CELL_SIZE - mouseX, 2) + Math.pow(rain.y * CELL_SIZE - mouseY, 2)
      );
  
      const attractionStrength = Math.min(0.5, Math.max(0, 100 - distanceToMouse)); // Very weak pull
      if (distanceToMouse < 400) {
        rain.dx += (mouseX - rain.x * CELL_SIZE) / 2000000 * attractionStrength;
        rain.dy += (mouseY - rain.y * CELL_SIZE) / 2000000 * attractionStrength;
      }
    }
  }
  

// Parallax effect for rain numbers
function updateRainParallax() {
  const parallaxSpeedFactor = 0.05; // Speed of parallax effect
  const mouseDistX = (mouseX - SCREEN_WIDTH / 2) * parallaxSpeedFactor;
  const mouseDistY = (mouseY - SCREEN_HEIGHT / 2) * parallaxSpeedFactor;

  rainGrid.forEach(rain => {
    rain.x += mouseDistX * rain.speed;
    rain.y += mouseDistY * rain.speed;
  });
}

function drawGrid() {
  ctx.fillStyle = "rgb(0, 0, 0)";
  ctx.fillRect(0, 0, SCREEN_WIDTH, SCREEN_HEIGHT);

  grid = buildFullGrid();

  // Draw the grid with the letters (foreground)
  for (let y = 0; y < rows; y++) {
    for (let x = 0; x < cols; x++) {
      const cell = grid[y][x];
      if (cell.alive) {
        ctx.font = `${FONT_SIZE}px o`;
        ctx.fillStyle = cell.color;
        ctx.fillText(cell.char, x * CELL_SIZE, y * CELL_SIZE + FONT_SIZE);
      }
    }
  }

  // Draw the matrix rain with parallax effect
  updateRainParallax();

  for (let i = 0; i < rainGrid.length; i++) {
    const x = rainGrid[i].x;
    const y = Math.floor(rainGrid[i].y);
    const char = rainGrid[i].char;
    const color = rainGrid[i].color;

    ctx.font = `${FONT_SIZE}px o`;
    ctx.fillStyle = color;

    const positions = [
      [x, y],
      [cols - x - 1, y],
      [x, rows - y - 1],
      [cols - x - 1, rows - y - 1],
      [y, x],
      [cols - y - 1, x],
      [y, cols - x - 1],
      [cols - y - 1, cols - x - 1],
    ];

    positions.forEach(([px, py]) => {
      if (px >= 0 && px < cols && py >= 0 && py < rows) {
        ctx.fillText(char, px * CELL_SIZE, py * CELL_SIZE + FONT_SIZE);
      }
    });
  }
}
function drawGalaxies() {
    for (let mirrorX = -1; mirrorX <= 1; mirrorX += 2) {
      for (let mirrorY = -1; mirrorY <= 1; mirrorY += 2) {
        ctx.save();
        ctx.translate(
          mirrorX === -1 ? SCREEN_WIDTH : 0,
          mirrorY === -1 ? SCREEN_HEIGHT : 0
        );
        ctx.scale(mirrorX, mirrorY);
  
        galaxies.forEach(galaxy => {
          galaxy.angle += galaxy.spin;
          galaxy.colorTime += 0.01;
  
          const r = Math.floor(Math.sin(galaxy.colorTime) * 127 + 128);
          const g = Math.floor(Math.sin(galaxy.colorTime + 2) * 127 + 128);
          const b = Math.floor(Math.sin(galaxy.colorTime + 4) * 127 + 128);
          const color = `rgb(${r}, ${g}, ${b})`;
  
          for (let a = 0; a < GALAXY_ARMS; a++) {
            const armAngle = (Math.PI * 2 / GALAXY_ARMS) * a + galaxy.angle;
  
            for (let i = 0; i < GALAXY_POINTS; i++) {
              const radius = i * 3;
              const theta = armAngle + i * 0.1;
              const dx = Math.cos(theta) * radius;
              const dy = Math.sin(theta) * radius;
  
              drawGalaxyChar(galaxy.x + dx, galaxy.y + dy, galaxy.char, color);
            }
          }
        });
  
        ctx.restore();
      }
    }
  }
  
  
  
function gameLoop() {
  updateQuarterGrid();
  updateRain(); // Updates the rain
  drawGrid();
  drawGalaxies(); 
  requestAnimationFrame(gameLoop);
}

// Start the animation
gameLoop();
