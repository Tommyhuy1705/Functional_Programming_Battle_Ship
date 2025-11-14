/**
 * Helper JS để lấy tọa độ DOM (offsetTop, offsetLeft) của một ô cờ
 * Hàm này được gọi từ Haskell/Threepenny
 */

window.getCellOffset = function(cellId) {
    const cell = document.getElementById(cellId);
    if (!cell) {
        return { top: 0, left: 0, error: "Cell not found: " + cellId };
    }
    
    // Lấy tọa độ tương đối so với viewport
    const rect = cell.getBoundingClientRect();
    
    // Lấy container board (cha của <table>)
    let container = cell.closest('.game-board').parentElement;
    if (!container) {
        container = cell.closest('table').parentElement;
    }
    
    const containerRect = container.getBoundingClientRect();
    
    // Tính toán tọa độ tương đối so với container
    const relativeTop = rect.top - containerRect.top;
    const relativeLeft = rect.left - containerRect.left;
    
    return {
        top: relativeTop,
        left: relativeLeft,
        error: null
    };
};
