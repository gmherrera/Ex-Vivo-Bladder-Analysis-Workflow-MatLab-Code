function z = baseline(y, lambda, p)
% % Data processing algorithm that performs baseline correction using 
% % asymmetric lease squares smoothing algorithm developed by Eilers and Boelens.
% % Version 1.0
% % Date: July 17, 2026
% % Author: G. Herrera
% % Contributions: Author wrote this matlab function based on the algorithm
% %    described by Eilers and Boelens (October 21, 2005).
% %        See: Eilers, P. H. C. and H. F. M. Boelens (2005). Baseline
% %             correction with asymmetric least squares smoothing.
% %             Leiden University Medical Centre Report 1(1): 1-24.
% %             https://www.researchgate.net/publication/
% %             228961729_Baseline_Correction_with_Asymmetric_Least_Squares_Smoothing
% %
% % The documentation below is from comments provided by Eilers and
% %         Boelens in the paper cited above.
% % % Estimate baseline with asymmetric least squares
% % y = signal of interest
% % m = length(y);
% % D = diff(speye(m), 2);
% % w = ones(m, 1);
% % for it = 1:10
% % W = spdiags(w, 0, m, m);
% % C = chol(W + lambda * D’ * D);
% % z = C \ (C’ \ (w .* y));
% % w = p * (y > z) + (1 - p) * (y < z);
% % end
% % There are two parameters: p for asymmetry and λ for smoothness. Both have to be
% % tuned to the data at hand. We found that generally 0.001 ≤ p ≤ 0.1 is a good choice
% % (for a signal with positive peaks) and 10^2 ≤ λ ≤ 10^9
% % , but exceptions may occur. In any
% % case one should vary λ on a grid that is approximately linear for log λ. Often visual
% % inspection is sufficient to get good parameter values.


m = length(y);
D = diff(speye(m),2);
w = ones(m,1);
for i = 1:10
    W = spdiags(w, 0, m, m);
    C = chol(W + lambda * D' * D);
    z= C\(C'\(w.*y));
    base(:,i)=z; % debugging/opimitzation; not returned as output in production
    w=p*(y>z)+(1-p)*(y<z);
end

end
